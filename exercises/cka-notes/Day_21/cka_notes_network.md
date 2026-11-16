# Day 15 — Networking (3): CNI, kube-proxy, DNS, Ingress, Gateway API

## CNI — IP assignment

IP assignment is delegated by the CNI plugin to an **IPAM plugin** (`host-local`, `dhcp`, `calico-ipam`…), set in the `ipam` section of the CNI config file.

### LAB — CNI (Flannel → Calico)

```bash
ls /etc/cni/net.d/                                      # where the config of the plugins lives
cat /etc/cni/net.d/10-flannel.conflist
kubectl get pods -o wide                                # display the pod IPs
```

Remove a CNI plugin — careful, it lives in its own namespace (here `kube-flannel`):

```bash
kubectl delete daemonset -n kube-flannel kube-flannel-ds
kubectl delete cm kube-flannel-cfg -n kube-flannel
rm /etc/cni/net.d/10-flannel.conflist                   # on EVERY node
ip link delete cni0; ip link delete flannel.1           # on every node: leftover interfaces
```

> Existing pods keep their old Flannel IP → recreate them after the switch.

Install Calico ([docs](https://docs.tigera.io/calico/3.31/getting-started/kubernetes/self-managed-onprem/onpremises#install-calico)):

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.6/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.6/manifests/tigera-operator.yaml
# create, not apply: CRDs too big for the last-applied annotation (or apply --server-side)
# remove with kubectl delete -f <same URL>

curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.31.6/manifests/custom-resources.yaml
vi custom-resources.yaml                                # Installation: ipPools cidr 192.168.0.0/16 -> 172.17.0.0/16
grep cluster-cidr /etc/kubernetes/manifests/kube-controller-manager.yaml   # the cidr must match the cluster pod CIDR
kubectl create -f custom-resources.yaml                 # dataplane: standard Linux (iptables) by default
watch kubectl get tigerastatus                          # wait until everything is Available

kubectl exec -it frontend -- curl -m 5 172.17.0.5       # times out: a NetworkPolicy denies it (Flannel ignored it, Calico enforces it)
```

---

## CNI vs kube-proxy

| | CNI | kube-proxy |
|---|---|---|
| Problem solved | pods reach each other by IP | a stable IP in front of pods that keep changing |
| When it acts | pod created/deleted (`ADD`/`DEL`) | Service / EndpointSlice changes |
| What it creates | veth, IP, routes, overlay | NAT rules (iptables / IPVS / nftables) |
| Runs as | binary called by containerd | DaemonSet in `kube-system` |

- **ClusterIP is virtual**: no interface holds it, not pingable.
- kube-proxy **reads** pod IPs, doesn't assign them: CNI gives the IP → kubelet reports `status.podIP` → Ready pods matching the selector go into an **EndpointSlice** → kube-proxy writes a **DNAT** rule `ClusterIP:port → podIP:targetPort` on **every node**.
- It doesn't proxy traffic: it programs the kernel (name comes from the old userspace mode). Cilium can replace it (eBPF).

```text
pod client → curl 10.96.0.50:80 (ClusterIP)
  → iptables of the CLIENT node: DNAT to 10.244.2.7:8080   (rule written by kube-proxy)
  → CNI: cni0 / overlay to the pod
  → reply: kernel undoes the NAT (conntrack)
```

> Debug split: pod unreachable by its IP → **CNI**. ClusterIP not answering → **kube-proxy / endpoints / selector**.

```bash
k get cm kube-proxy -n kube-system -o yaml | grep mode     # "" = iptables (default)
k get endpointslices -l kubernetes.io/service-name=<svc>   # empty = selector / readiness problem
iptables -t nat -L KUBE-SERVICES -n | grep <clusterIP>     # the Service rule
```

### Traffic from outside

The kube-proxy rule is applied on the node **where the packet enters**. ClusterIP ⊂ NodePort ⊂ LoadBalancer.

- **NodePort**: `<nodeIP>:30080` → DNAT to any pod. If the pod is on another node, the entry node also **SNATs** → pod doesn't see the client IP.
- `externalTrafficPolicy`: `Cluster` (default) = any pod, client IP lost · `Local` = only local pods, client IP kept, node without pod refuses traffic.
- **No cloud**: `type: LoadBalancer` stays `<pending>` until MetalLB / k3s ServiceLB / k3d LB implements it.
- **AWS** (out of CKA scope): AWS Load Balancer Controller pushes targets to the ALB/NLB via the AWS API. `instance` mode = all nodes on the NodePort (kube-proxy redistributes) · `ip` mode = pod IPs directly, kube-proxy bypassed (use pod readiness gates against 502s on rolling updates).

---

## DNS

- Pod `/etc/resolv.conf`: `nameserver` = CoreDNS Service IP (`kube-dns`) · `search <ns>.svc.cluster.local svc.cluster.local cluster.local` → short names get these domains appended.
- Names: Service `<svc>.<ns>.svc.cluster.local` · pod `10-244-1-5.<ns>.pod.cluster.local`. Short name `web-service` works **only in the same namespace**, otherwise `web-service.<ns>`.
- CoreDNS = Deployment in `kube-system`, config (Corefile) in ConfigMap `coredns`.

```bash
k exec -it test -- curl -m 5 web-service                         # test connectivity (same ns)
k run tmp --rm -it --image=busybox -- nslookup web-service.<ns>  # test resolution
```

---

## Ingress

The **Ingress controller** (nginx, Traefik…) is the reverse proxy of the cluster: it runs as pods, is itself exposed via a NodePort/LoadBalancer Service, terminates TLS and forwards each HTTP request to the right **Service** based on the **host and path** rules defined in **Ingress resources**. No controller installed = Ingress resources do nothing.

To run, the controller needs:

| Object | Role |
|---|---|
| Deployment | image, args, replicas, listening ports |
| Service | exposes the ports |
| ConfigMap | configuration |
| ServiceAccount + (Cluster)Role + binding | access to Ingress objects etc. (an SA alone grants nothing) |
| IngressClass | links Ingress resources to the controller (`k get ingressclass`) |
| Ingress resources | rules per host and/or path |

- **Annotations are controller-specific**: `nginx.ingress.kubernetes.io/*` are ignored by Traefik's default provider (k3s/k3d → `Middleware` `stripPrefix`), but understood by Traefik's **Kubernetes Ingress NGINX provider** (the lab setup, `nginx` IngressClass).
- **Redirect vs rewrite**:

| Annotation | Effect |
|---|---|
| `app-root: /pay` | **redirect** (302 to the client), only for `/` exactly → `/pay` |
| `rewrite-target: /` | **rewrite** inside nginx: client asks `/pay`, backend receives `/` (sub-path lost; keep it with `path: /pay(/\|$)(.*)` + `rewrite-target: /$2`) |

Course notes: [Udemy lecture](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/learn/lecture/16827080#overview)

### LAB — Ingress

```bash
k edit ingresses.networking.k8s.io -n app-space ingress-wear-watch     # see ./ingress_rule.yaml

kubectl create ingress critical-ingress -n critical-space --rule="/pay=pay-service:8282" --dry-run=client -o=yaml \
  --annotation nginx.ingress.kubernetes.io/ssl-redirect="false" \
  --annotation nginx.ingress.kubernetes.io/rewrite-target=/ > rewrite.yaml   # see ./rewrite.yaml
# ssl-redirect=false: no automatic HTTP -> HTTPS redirect · no --class: needs a default IngressClass

kubectl create ingress web-app-ingress -n webapp --rule="app.kodekloud.local/*=web-app:80" --dry-run=client -o=yaml --class=nginx > webapp.yaml
```

> `--rule` pitfall: `/pay` → `pathType: Exact` (`/pay/xyz` doesn't match), `/pay*` → `Prefix`. Same for `host/` vs `host/*`.

---

## Gateway API

With Ingress, advanced features (rewrite, redirect…) rely on **controller-specific annotations**. The Gateway API standardizes them (`HTTPRoute` filters `URLRewrite`, `RequestRedirect`), is more declarative and splits roles. Ingress is frozen but still GA. Not every provider supports it yet, most do.

| Object | Owner | Content |
|---|---|---|
| `GatewayClass` | infra provider | which controller |
| `Gateway` | cluster operator | listeners (protocol, port, hostname, TLS) |
| `HTTPRoute` | app team | `parentRefs` (Gateway), `matches` (path/header), `backendRefs` (Service:port) |

Course notes: [Udemy lecture — LAB Gateway API](https://www.udemy.com/course/certified-kubernetes-administrator-with-practice-tests/learn/lecture/50127829#overview)

### LAB — Gateway API (NGINX Gateway Fabric)

```bash
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v1.5.1" | kubectl apply -f -   # Gateway API standard CRDs
kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v1.6.1/deploy/crds.yaml            # NGF's own CRDs
kubectl apply -f https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/v1.6.1/deploy/nodeport/deploy.yaml # controller, exposed as NodePort
# lab mixes v1.5.1 / v1.6.1: align the versions in real life

kubectl get pods -n nginx-gateway
kubectl get svc -n nginx-gateway nginx-gateway -o yaml  # check the port order before patching
kubectl patch svc nginx-gateway -n nginx-gateway --type='json' -p='[
  {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080},
  {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 30081}
]'                                                      # ports/0 = http, ports/1 = https (as listed above)
```

---

## To review

- [ ] Swap the CNI (Flannel → Calico): cleanup on every node, pod CIDR check, NetworkPolicy now enforced
- [ ] Explain CNI vs kube-proxy in one sentence each; find the DNAT rule of a Service in `iptables -t nat`
- [ ] Empty EndpointSlice → fix the selector / readiness
- [ ] NodePort with `externalTrafficPolicy: Cluster` vs `Local`
- [ ] DNS: resolve a Service from another namespace with `nslookup`, read a pod's `resolv.conf`, find the CoreDNS Corefile
- [ ] `kubectl create ingress` with `Exact` vs `Prefix` (`*`), `--class`, `--annotation`
- [ ] `rewrite-target` vs `app-root` from memory
- [ ] Gateway API: write a `Gateway` + `HTTPRoute` (path match, backendRefs) from the docs — not done in the lab yet