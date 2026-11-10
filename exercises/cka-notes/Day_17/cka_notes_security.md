# Day 11 — Security: authorization, RBAC, images, security context, network policies

## API

- `kubectl proxy`: creates a proxy on `127.0.0.1:8001` using the kubeconfig file → curl the API without passing credentials.
- **API groups**: core group = `""` (served at `/api/v1`: pods, svc, cm, secrets), every other group is named (`/apis/<group>/<version>`, e.g. `apps/v1`, `networking.k8s.io/v1`) → `k api-resources -o wide` / `k explain <kind>` show the group, the version and the verbs.

---

## Authorization

Main modes: Node, ABAC, RBAC, Webhook.

| Mode | What it does |
|---|---|
| **Node** | Authorizes kubelets (user `system:node:<nodeName>`, group `system:nodes`). |
| **ABAC** | Static JSON policy file on the apiserver (`--authorization-policy-file`), one rule per user/group; any change = edit the file + restart the apiserver. Legacy, rarely used. |
| **RBAC** | Permissions defined once in a `Role`/`ClusterRole`, attached to users/groups/SAs via bindings; API objects, changes apply instantly with `kubectl apply`. |
| **Webhook** | Outsources the authorization decision to an external agent. |

- **Authorization modes**: `--authorization-mode=Node,RBAC` is evaluated in order and the first "allow" wins; if nothing allows, the request gets a 403 (default deny, allow-only rules, no explicit deny). `AlwaysAllow` / `AlwaysDeny` allow or deny everything (test/lab only).
- **Default mode**: a bare `kube-apiserver` defaults to `AlwaysAllow` (legacy), but installers override it (kubeadm/k3s/EKS → `Node,RBAC`). Check it with `grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml`.

---

## RBAC

Steps:

1. Create a user and/or a group
2. Create a Role
3. Create a binding linking the Role and the users / groups

Roles and RoleBindings live inside a namespace → mind the namespace when creating them.

```bash
kubectl auth can-i <verb> <subcommand>       # k auth can-i create deployments -> yes / no
kubectl auth can-i create pods --as <user>   # impersonate a user
k get/describe roles/rolebindings
```

- **RBAC matching**: the authorizer infers nothing, it matches the exact group + resource pair → `apiGroups` is required (omitted = Role rejected, wrong group = accepted but `Forbidden`, e.g. `deployments` under `[""]` instead of `apps`). `k create role --resource=deployments` fills in the right group automatically; otherwise check with `k api-resources`.
- **Core group in RBAC**: `apiGroups: [""]` for core resources (pods, services, configmaps, secrets, nodes…). In `k api-resources`, they show `APIVERSION v1` with no `group/` prefix.
- **resourceNames**: exact match only, no wildcard or prefix (`blue-`* and `"*"` are taken literally) → list every name, or remove the field to allow everything. Doesn't apply to `create` (the name doesn't exist yet) or to a full `list`/`watch`.
- **Deleting a (Cluster)Role doesn't delete its bindings**: they stay dangling and grant nothing, but recreating a role with the same name reactivates them → delete the bindings too. `roleRef` is immutable (delete + recreate the binding to change it).
- **RBAC exam flow**: `k create (cluster)role X --resource=a,b --verb=v1,v2` → `k create (cluster)rolebinding Y --(cluster)role=X --user=U` → always verify with `k auth can-i <verb> <resource> --as U`. Only the verbs asked.

### LAB — RBAC

```bash
cat /etc/kubernetes/manifests/kube-apiserver.yaml                      # - --authorization-mode=Node,RBAC
k get roles -A --no-headers | wc                                       # count roles (first column = line count)
k describe roles.rbac.authorization.k8s.io kube-proxy -n kube-system   # careful with the namespace
kubectl describe rolebinding kube-proxy -n kube-system                 # the binding tells which users/groups get the role

kubectl create role developer --verb=get,create,delete --resource=pods --dry-run=client -o yaml > developer.yaml
kubectl create rolebinding dev-user-binding --role=developer --user=dev-user --dry-run=client -o yaml > dev-user-binding.yaml   # --role, not --clusterrole: developer is a Role
k apply -f developer.yaml -f dev-user-binding.yaml

k create role test --verb=create --resource=deployments --dry-run=client -o=yaml   # generates the rule with the right apiGroup (apps)
k edit role developer -n blue                                                      # paste that rule into the rules array
```

---

## Cluster Roles

**Important** — discover which resources are namespaced or cluster-scoped:

```bash
kubectl api-resources --namespaced=true    # or =false
```

- **Cluster-scoped resources** (nodes, PVs, namespaces, CRDs…): access can only be granted with a ClusterRole + ClusterRoleBinding (a Role can't target them).
- **Scope = the binding, not the role**:

| Role | Binding | Scope for namespaced resources (pods…) |
|---|---|---|
| ClusterRole | ClusterRoleBinding | **all** namespaces |
| ClusterRole | RoleBinding | only the RoleBinding's namespace (reusable template, e.g. `view`/`edit`) |
| Role | RoleBinding | the Role's namespace only |

### LAB — Cluster roles

```bash
k get clusterrolebindings.rbac.authorization.k8s.io --no-headers | wc
k describe clusterrolebindings.rbac.authorization.k8s.io cluster-admin
kubectl api-resources -o wide | grep node    # list available verbs for the node resource

k create clusterrole nodes_admin --resource=nodes --verb=create,delete,deletecollection,get,list,patch,update,watch --dry-run=client -o=yaml
```

Granting all rights to user michelle on persistentvolumes and storageclasses:

```bash
k api-resources -o wide | grep storageclasses       # list verbs and verify syntax
k api-resources -o wide | grep persistentvolumes    # list verbs and verify syntax

k create clusterrole storage-admin --resource=persistentvolumes --verb=create,delete,deletecollection,get,list,patch,update,watch --resource=storageclasses --verb=create,delete,deletecollection,get,list,patch,update,watch --dry-run=client -o=yaml > storage-admin.yaml
# equal to this:
k create clusterrole storage-admin --resource=persistentvolumes,storageclasses --verb='*' --dry-run=client -o=yaml > storage-admin.yaml

k create clusterrolebinding storage-admin-binding --user=michelle --clusterrole=storage-admin --dry-run=client -o=yaml > storage-admin-binding.yaml

k apply -f storage-admin.yaml -f storage-admin-binding.yaml
k auth can-i get persistentvolumes --as michelle    # verification
```

---

## LAB — Service accounts

```bash
k get serviceaccounts
k create serviceaccount dashboard-sa
kubectl create token dashboard-sa
cat /var/rbac/dashboard-sa-role-binding.yaml
```

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: read-pods
  namespace: default
subjects:
- kind: ServiceAccount
  name: dashboard-sa        # case sensitive
  namespace: default
roleRef:
  kind: Role                # Role or ClusterRole
  name: pod-reader          # must match the name of the Role/ClusterRole to bind to
  apiGroup: rbac.authorization.k8s.io
```

Use the service account in the deployment: `spec.template.spec.serviceAccountName: dashboard-sa` (`serviceAccount` is deprecated), or `k set serviceaccount deploy/<name> dashboard-sa`.

Disabling automatic mounting of API credentials:

```bash
k edit serviceaccount dashboard-sa    # add at root level: automountServiceAccountToken: false
```

Then mount the token explicitly with a projected volume (https://kubernetes.io/docs/concepts/storage/projected-volumes/), in the deploy.yaml:

```yaml
        volumeMounts:
        - mountPath: /var/run/secrets/kubernetes.io/serviceaccount/
          name: token
          readOnly: true
      serviceAccountName: dashboard-sa
      automountServiceAccountToken: false
      volumes:
      - name: token
        projected:
          sources:
          - serviceAccountToken:
              path: token
```

---

## Image security

- `image: <name>` really means `docker.io/library/<name>`. `gcr.io` is the Google registry.
- Registries can be public or private (so far all were public). For a private one you authenticate first (`docker login <private-repo>.io`).
- In Kubernetes: create a `docker-registry` secret (server, username, password, email); the kubelet passes these credentials to the container runtime (containerd) that pulls the image.
- The secret is referenced at **pod level**: `spec.imagePullSecrets: [{name: <secret>}]`.

```bash
k create secret docker-registry private-reg-cred \
  --docker-server=myprivateregistry.com:5000 \
  --docker-username=dock_user \
  --docker-password=dock_password \
  --docker-email=dock_user@myprivateregistry.com
```

```yaml
spec:
  containers:
  - name: private-reg-container
    image: <your-private-image>
  imagePullSecrets:
  - name: private-reg-cred
```

---

## Security context

- Container root is the same UID 0 as the machine root, but with a reduced set of capabilities (unless `privileged: true`).
- Declared at pod level, `spec.securityContext`, or at container level, `spec.containers[].securityContext` (the container level wins).
- **Capabilities can only be set at container level**, not at pod level.

```bash
cat /usr/include/linux/capability.h        # list capabilities
kubectl exec ubuntu-sleeper -- whoami      # discover the user of the container
```

---

## Network policy

- By default all traffic is allowed everywhere (across pods, nodes, services). Network policies restrict this; they are linked to pods through labels.
- **Attention**: once a policy selects a pod, the pod is isolated only in the directions listed in `policyTypes`. `Ingress` listed with no ingress rule = all ingress denied; `Ingress` not listed = ingress stays fully open. Don't drop a type just because its rule list is empty.
- Types of selector: `podSelector`, `namespaceSelector`, `ipBlock`.
- **Selectors in** `from`**/**`to`: `podSelector` alone = pods of the policy's own namespace only (tested: same label in another namespace is blocked); `namespaceSelector` alone = all pods of those namespaces. Namespaces are matched by label (`kubernetes.io/metadata.name: <ns>` exists by default).
- **Attention**: under `from`/`to`, each `-` is one peer. Selectors inside the same `-` are ANDed (`namespaceSelector` + `podSelector` = those pods in those namespaces); two separate `-` are ORed (either one is enough).
- `ports` **belongs to the rule, not to the peer**: same level as `to`/`from`. Different port per destination → one rule (`- to:` + `ports:`) per destination; several peers in one rule share all its ports.
- **NetworkPolicies are stateful**: a rule allows a connection in the direction it's initiated, replies are allowed implicitly (like AWS Security Groups, unlike NACLs) → `Ingress`/`Egress` = who opens the connection. Egress policy on a pod → remember to allow DNS (port 53 UDP/TCP).
- **Why stateful**: NetworkPolicies are enforced on the node by the CNI (iptables/eBPF + conntrack), which tracks connections → replies pass automatically. A stateless filter (NACL) checks each packet alone → return traffic on ephemeral ports must be allowed by hand. No enforcement if the CNI doesn't support policies (e.g. Flannel alone).

### LAB — Network policy

```bash
k get networkpolicies.networking.k8s.io
# NAME             POD-SELECTOR   AGE
# payroll-policy   name=payroll   20s

k get pods --selector=name=payroll
k get pods --show-labels                  # check the real label keys before writing selectors
```

Egress policy: internal app → payroll (8080) and mysql (3306) only, plus DNS:

See [Network policy file](exercises/cka-notes/Day_17/NetworkPolicy.yaml)

---

## To review

- [ ] Redo the RBAC lab without notes: role + rolebinding in a namespace, then `auth can-i --as`
- [ ] Write a Role by hand with two rules (core group + `apps`) and `resourceNames`
- [ ] ClusterRole + RoleBinding vs ClusterRoleBinding: test the scope of each
- [ ] Service account: token, `serviceAccountName`, disable automount + projected volume
- [ ] Private registry: `docker-registry` secret + `imagePullSecrets` from memory
- [ ] Security context: `runAsUser` at pod vs container level, add a capability
- [ ] Write a NetworkPolicy from the docs example: ingress + egress, AND vs OR peers, one port per destination, DNS
- [ ] Redo the cross-namespace test (`podSelector` alone vs with `namespaceSelector`)
