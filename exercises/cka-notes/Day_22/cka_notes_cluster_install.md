# Day 16 — Creating a Kubernetes cluster (kubeadm)

## Choosing a setup

| Use | Setup |
|---|---|
| Education | Minikube, or a single-node cluster with kubeadm |
| Testing | single master + multiple workers with kubeadm (local), or quick provisioning on a cloud (GKE / EKS / AKS) |
| Production | high availability with multiple masters — kubeadm, or kOps on AWS |

- **Limits**: up to 5,000 nodes, 150,000 pods, 300,000 containers in total, 110 pods per node (default kubelet `maxPods`).
- **On-prem**: kubeadm is a solid option. **Cloud**: GKE (GCP), EKS (AWS; kOps is the self-managed alternative), AKS (Azure). All offer one-click deploy and upgrade.

### Distributions: OpenShift (and EKS)

- **OpenShift** = Red Hat's Kubernetes distribution (paid subscription; **OKD** = free community upstream). Standard Kubernetes inside (`kubectl` works, `oc` extends it) + opinionated built-ins: RHCOS nodes, CRI-O, OVN-Kubernetes, **Routes**, **SCC** (non-root by default), OAuth server, internal registry, **OperatorHub/OLM**, monitoring, web console.
- **Use case**: internal PaaS for large companies that stay **on-prem** (regulation, sovereignty, own datacenters): banks, insurance, public sector, telco, industry. Self-service for many dev teams, small platform team, one vendor accountable. Also **hybrid** (same platform on-prem and in the cloud) and **VMware exit** (OpenShift Virtualization = KubeVirt).
- (**EKS vs ROSA**: EKS = AWS runs the control plane, you assemble the add-ons → default when starting from scratch on AWS. ROSA = OpenShift on AWS run by Red Hat SREs, billed through AWS → chosen for continuity with an on-prem OpenShift; more expensive.)
- Not in CKA scope. AWS ↔ OpenShift service mapping: [`openshift_vs_aws.md`](openshift_vs_aws.md).

---

## Nodes & storage

Storage type matters. Label nodes by disk type and use `nodeSelector` / affinity to place apps on them:

| Need | Storage |
|---|---|
| high performance | SSD |
| many concurrent connections | network-based storage |
| shared access across multiple pods | persistent shared storage |

- Nodes can be virtual or physical.
- The master can run workloads but shouldn't. kubeadm taints it (`node-role.kubernetes.io/control-plane:NoSchedule`).
- With a single master, all control-plane components live on that node → single point of failure → use multiple masters for HA.

---

## High availability

| Component | HA mode |
|---|---|
| kube-apiserver | **active-active** behind a load balancer. Configured with the list of etcd endpoints. |
| controller-manager & scheduler | **active-passive** via leader election (lease 15s, renew deadline 10s, retry every 2s) |
| etcd | **stacked** (on the masters) or **external** topology |

etcd leader/followers model:
- API servers can read from and send writes to any etcd member
- followers forward writes to the leader
- only the leader writes; it replicates to the followers and commits once a majority acknowledges (**quorum = floor(N/2) + 1**)
- leader election uses **Raft**
- use an odd number of members: 3 tolerates 1 failure, 5 tolerates 2

---

## Installing with kubeadm

1. On every node: container runtime (containerd + crictl), then kubeadm, kubelet and kubectl
2. Prepare the kernel (every node)
3. `kubeadm init` on the master
4. Install the pod network (CNI)
5. `kubeadm join` on the workers

### Runtime (every node)

```bash
# containerd.io ships a minimal config with CRI disabled -> regenerate the full default config (overwrites the existing one)
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
# cgroup driver must match the kubelet's (systemd with kubeadm)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
grep -n SystemdCgroup /etc/containerd/config.toml   # same key on containerd 2.x, different section path
```

> ⚠️ My first version (`cat … | sed … | tee config.toml` + `mv`) never restarted containerd: the old daemon kept running with the old config. Use `sed -i` in place.

### kubeadm, kubelet, kubectl (every node)

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
# repo per minor: same minor on every node as the control plane (version skew)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-get install -y cri-tools                   # crictl: not pulled by the kubeadm packages (fallback: ctr version)
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

### Kernel (every node)

```bash
sudo swapoff -a                                     # kubelet refuses to start with swap on (default)
sudo sed -i '/ swap / s/^/#/' /etc/fstab            # persistent
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k8s.conf
sudo modprobe overlay && sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system                                # reload all sysctl files
cat /proc/sys/net/ipv4/ip_forward                   # must print 1
```

### Init / CNI / join

```bash
kubeadm init --control-plane-endpoint 10.244.154.7 --pod-network-cidr 172.17.0.0/16 --upload-certs
# --control-plane-endpoint = shared address (LB IP/DNS in HA, needed to add masters later)
# --apiserver-advertise-address = IP of this node

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# flannel defaults to 10.244.0.0/16 -> edit net-conf.json "Network" in flannel.yaml to match --pod-network-cidr BEFORE applying
k apply -f flannel.yaml

# on the workers
kubeadm join 10.244.154.7:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
kubeadm token create --print-join-command           # lost the command? (token expires after 24h)
kubeadm reset -f                                    # before retrying a failed init / join
```

---

## Troubleshooting log (lab of 2026-11-17)

**containerd never restarted** — `policy-rc.d returned 101`: in the lab, apt installs/upgrades packages without restarting services → always restart the service yourself after a package upgrade.

**CNI image pull fails**: `lookup ghcr.io on 10.96.0.10:53 … operation not permitted`
- Image pulls are done by **containerd on the node**, using the node's `/etc/resolv.conf`.
- In the lab the "nodes" are themselves pods of an outer cluster → their `resolv.conf` points to the outer CoreDNS `10.96.0.10`, the same IP as the inner cluster's kube-dns.
- The inner kube-proxy REJECTs traffic to a Service with no endpoints → `sendto()` returns EPERM. CoreDNS can't start without a CNI → deadlock.
- Fix (lab-only workaround, **on every node**): `echo "nameserver 8.8.8.8" > /etc/resolv.conf`. Use `>`, not `sed -i`: `resolv.conf` is a bind mount and can't be renamed over.
- Lesson: **cluster DNS is for pods, not for nodes.**

**kubectl before init or on a worker** → error is normal: no apiserver / no admin kubeconfig yet (`NotFound` here = lab-provided kubeconfig pointing elsewhere; check with `kubectl config view --minify`). Run kubectl from the control plane (or copy `/etc/kubernetes/admin.conf`).

**Node NotReady + flannel pod stuck `Init:0/2`**: no CNI config in `/etc/cni/net.d` yet. Flannel is a DaemonSet (one pod per node, installs the CNI locally). After fixing the cause, delete the pod to skip the image-pull backoff.

**`failed to start shim … built against the new API`**: the running containerd daemon is older than the `containerd-shim-runc-v2` binary on disk (package upgraded, daemon not restarted). The earlier preflight warning about `RuntimeConfig` was the same symptom.
- Fix: `systemctl restart containerd kubelet`, and check `which -a containerd containerd-shim-runc-v2` for duplicates.

Useful commands:

```bash
crictl pull / ps / logs
k describe node
k -n kube-flannel get pods -o wide
iptables-save | grep <svc-ip>
kubectl get nodes -v=6
```

---

## To review

- [ ] Redo the full install without notes: runtime → packages → kernel → init → kubeconfig → CNI → join
- [ ] containerd config: CRI enabled, `SystemdCgroup = true`, restart, verify (`crictl version` / `ctr version`)
- [ ] `kubeadm init` flags: `--control-plane-endpoint` vs `--apiserver-advertise-address`, `--pod-network-cidr` = CNI CIDR
- [ ] Regenerate a join command, `kubeadm reset -f`
- [ ] HA: apiserver active-active vs CM/scheduler leader election, etcd stacked vs external, quorum formula
- [ ] Debug a NotReady node: `/etc/cni/net.d`, `crictl ps -a`, `journalctl -u kubelet`
- [ ] Kubernetes the hard way: https://github.com/mmumshad/kubernetes-the-hard-way
