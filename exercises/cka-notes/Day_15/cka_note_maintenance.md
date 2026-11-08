# Day 9 — Cluster maintenance

## Node maintenance: drain / cordon / uncordon

| Command | Effect |
|---|---|
| `kubectl drain <node> --ignore-daemonsets` | Marks the node **unschedulable** + **evicts** its pods (respects PodDisruptionBudgets). Pods managed by a controller get recreated elsewhere; bare pods are lost (`--force` needed). |
| `kubectl cordon <node>` | Only marks the node unschedulable. Running pods stay. |
| `kubectl uncordon <node>` | Makes the node schedulable again. **Does not move pods back**: only new pods land on it. |

- If a node stops responding, its pods are evicted after **5 min** by default (taint-based eviction, `tolerationSeconds: 300`).
- `--ignore-daemonsets` is required because DaemonSet pods can't be evicted (the controller would immediately recreate them).

---

## Version skew policy

Everything is relative to the **kube-apiserver** version (X). No component may be newer than the apiserver, except kubectl.

| Component | Allowed versions | Example with apiserver v1.10 |
|---|---|---|
| kubectl | X+1 / X / X-1 | v1.9 → v1.11 |
| **kube-apiserver** | **X** | **v1.10** |
| controller-manager, kube-scheduler | X / X-1 | v1.9 → v1.10 |
| kubelet, kube-proxy | X → X-3 | v1.7 → v1.10 |

**Consequence → upgrade order:** control plane first (apiserver, then CM/scheduler), then the kubelets on every node.

### Support & cadence

- Kubernetes maintains only the **3 most recent minor versions** (e.g. once 1.13 is out, 1.10 is no longer supported).
- With kubeadm you upgrade **one minor at a time** (1.34 → 1.35 → 1.36). You cannot skip minors.
- Good practice: stay at most 1 minor behind the latest release.

### Impact of upgrading the control plane

- Workloads **keep running** (containers don't depend on the API).
- But while it's down: **no kubectl**, no reconciliation (a crashed pod isn't recreated), no scheduling of new pods.
- With an HA control plane (several masters behind an LB), there's no API downtime.

---

## LAB — Upgrade a kubeadm cluster (1.34 → 1.35)

### 0. Pre-checks

```bash
k get nodes
k describe nodes | grep -i taint     # can the control plane run workloads?
k get deploy,pods -A -o wide         # what runs where, will it be recreated elsewhere?
```

Make sure there are enough nodes for pods to move (zero downtime) and that everything is managed by a controller.

### 1. Control plane — kubeadm

The apt repo is **per minor** (`pkgs.k8s.io/core:/stable:/v1.34/deb/`). To see 1.35 you need to switch repos.

```bash
sed -i 's#/v1.34/#/v1.35/#' /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm            # list available versions -> gives the exact package string (1.35.10-1.1)

apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.10-1.1
apt-mark hold kubeadm

kubeadm upgrade plan                 # check: target versions, components that will be upgraded
kubeadm upgrade apply v1.35.10       # upgrades static pods (apiserver, CM, scheduler, etcd) + addons (CoreDNS, kube-proxy)
```

> `kubeadm upgrade plan` only shows the latest patch reachable with the installed kubeadm → that's why you upgrade the kubeadm package **first**.

At this point:

```text
controlplane ~ ➜  k version
Client Version: v1.34.1      <- kubectl not upgraded yet (X-1 = OK)
Server Version: v1.35.10     <- apiserver upgraded
```

### 2. Control plane — kubelet + kubectl

```bash
k drain controlplane --ignore-daemonsets

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.35.10-1.1 kubectl=1.35.10-1.1
apt-mark hold kubelet kubectl

systemctl daemon-reload              # systemd re-reads unit files (the new package can ship a modified 10-kubeadm.conf)
systemctl restart kubelet            # starts the new kubelet binary

k get nodes -w                       # the node goes back to Ready with v1.35 (API can be briefly unreachable during the restart)
k uncordon controlplane
```

### 3. Worker node

```bash
k drain node01 --ignore-daemonsets   # from the control plane
k get pods -o wide -w                # pods are recreated on controlplane

ssh node01

sed -i 's#/v1.34/#/v1.35/#' /etc/apt/sources.list.d/kubernetes.list
cat /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-cache madison kubeadm

apt-mark unhold kubeadm
apt-get install -y kubeadm=1.35.10-1.1
apt-mark hold kubeadm

kubeadm upgrade node                 # updates the local kubelet config (/var/lib/kubelet/config.yaml)
                                     # on an extra control plane: also upgrades its static pods

apt-mark unhold kubelet
apt-get install -y kubelet=1.35.10-1.1
apt-mark hold kubelet

systemctl daemon-reload
systemctl restart kubelet

exit
k uncordon node01                    # back on the control plane — don't forget it!
```

### Which daemon gets restarted?

**Only the kubelet**, on every node (control plane and workers). It's the only K8s component running as a **systemd service**.

- **kube-proxy** → a **DaemonSet** in `kube-system`, upgraded by `kubeadm upgrade apply` (addon). Never restarted by hand.
- **containerd** → not touched by a K8s upgrade (only if you upgrade containerd itself).
- **apiserver / CM / scheduler / etcd** → **static pods**: kubeadm swaps their manifests in `/etc/kubernetes/manifests/` and the kubelet recreates them.

---

## Backup & restore

### Why not `kubectl get all -A -o yaml > backup.yaml` + `apply`?

1. **`get all` isn't all**: only pods, svc, deploy, rs, sts, ds, jobs, cronjobs, hpa. Missing: ConfigMaps, Secrets, PVC/PV, RBAC, ServiceAccounts, Ingress, NetworkPolicies, CRDs + CRs, namespaces, cluster-scoped objects…
2. **Live state, not desired state**: `status`, `uid`, `resourceVersion`, `managedFields`, `ownerReferences`, `clusterIP`… → conflicts on re-apply, and pods + RS + Deployments applied together = duplicates/orphans. No ordering (namespaces → CRDs → CRs).
3. **Not consistent**: sequential reads while the cluster keeps changing. An etcd snapshot is atomic.

| Need | Tool |
|---|---|
| Rebuild apps & config | **GitOps** (Git = source of truth, ArgoCD) |
| Proper API-level backup | **Velero** (ex Heptio Ark): all types, order, + PV data |
| DR of the control plane | **etcd snapshot** |

### What's in etcd

- **Every API object**, under keys like `/registry/<resource>/<namespace>/<name>` (`etcdctl get /registry --prefix --keys-only`).
- Not your YAML: the object **as accepted by the apiserver** (spec + defaults + webhook mutations + metadata + status), serialized as **protobuf** (JSON for CRs).
- Includes **Secrets** (base64 only unless encryption at rest) → an etcd snapshot is **sensitive**.

### What's NOT in etcd

| Not in etcd | Where |
|---|---|
| Volume data | disk / storage backend |
| **PKI** (CA, certs, `sa.key`) | `/etc/kubernetes/pki/` |
| kubeconfigs | `/etc/kubernetes/*.conf` |
| Static pod manifests | `/etc/kubernetes/manifests/` |
| Kubelet / CNI config | `/var/lib/kubelet/`, `/etc/cni/` |
| Containers & images | containerd on each node |
| External resources (LB, DNS) | the cloud provider |

→ An etcd restore restores the **state** of the cluster, not the cluster. A real kubeadm DR backup = **etcd snapshot + `/etc/kubernetes/pki` + volume data**.

### When to restore etcd (last resort: rolls back EVERYTHING, for everyone)

- etcd data lost/corrupted, quorum lost for good (2 of 3 members dead)
- Destructive mistake at scale: `delete ns`, **CRD deleted (→ all its CRs deleted)**, `delete --all` in the wrong context
- Failed control plane upgrade (`kubeadm upgrade apply` saves an etcd backup in `/etc/kubernetes/tmp/` for that)
- Security incident (rollback to a known-good state, then rotate secrets)
- Rebuilding a dead control plane (with the PKI backup)

**Not** for: one broken app (→ Git / `rollout undo`), lost volume data, migrating apps (→ Velero/GitOps).
On **EKS**: no access to etcd (managed by AWS) → GitOps + Velero / AWS Backup + EBS snapshots.

### Backup (snapshot save)

Take the flags from `/etc/kubernetes/manifests/etcd.yaml` (`--listen-client-urls`, `--trusted-ca-file`, `--cert-file`, `--key-file`).

```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/snapshot-pre-boot.db

etcdutl snapshot status /opt/snapshot-pre-boot.db -w table   # verify the snapshot
```

### Restore procedure (kubeadm, stacked etcd)

```bash
# 1. Stop the apiserver: move its manifest out of the folder watched by the kubelet (rescan ~20s)
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ && sleep 30

# 2. Restore the snapshot into a NEW data dir (this is the restore, not the backup)
etcdutl snapshot restore /opt/snapshot-pre-boot.db --data-dir /var/lib/etcd-from-backup

# 3. Point etcd to the restored data: only the hostPath changes
vi /etc/kubernetes/manifests/etcd.yaml
```

```yaml
  volumes:
  - hostPath:
      path: /etc/kubernetes/pki/etcd
      type: DirectoryOrCreate
    name: etcd-certs
  - hostPath:
      path: /var/lib/etcd-from-backup   # was /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

> The `mountPath` inside the container stays `/var/lib/etcd` → no need to touch `--data-dir`.

```bash
# 4. Wait for the kubelet to recreate the etcd container (new CONTAINER ID, Running)
watch crictl ps --name etcd

# 5. Bring the apiserver back
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# 6. Restart CM/scheduler/kubelet: their informer cache (LIST + WATCH from resourceVersion)
#    is stale after etcd went back in time -> restart forces a fresh LIST
mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/
mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/
sleep 20
mv /tmp/kube-controller-manager.yaml /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/
systemctl restart kubelet
```

**Why restart them if `k get pods` already looks fine after step 5?**
- kubectl reads etcd through the apiserver, which was restarted → fresh cache → it shows exactly the snapshot content.
- That says nothing about the controllers' caches: they only show their staleness when they have to **act** (recreate a pod, scale, schedule). Test: `k delete pod …`, `k scale deploy … --replicas=4`, `k get events`.
- The `Running` status is the one stored in the snapshot, not necessarily reality → truth on the node = `crictl ps`.
- Recent `etcdutl` versions: `snapshot restore --bump-revision <n> --mark-compacted` fixes this cleanly (watchers get "compacted" and re-LIST). The manual restart stays the classic lab/exam method.

### `watch crictl ps --name etcd`

- `watch`: Linux tool, reruns the command every 2s (`Ctrl+C` to quit)
- `crictl`: CLI talking **directly to the container runtime** (containerd) via CRI — `docker ps` equivalent, without going through the API
- Useful because during the restore the **apiserver is down → kubectl doesn't work**

```bash
crictl ps -a --name etcd          # -a: include Exited containers (crash loop)
crictl logs <container-id>        # why it doesn't start
crictl ps --name kube-apiserver
journalctl -u kubelet -f          # the kubelet side
```

> When the apiserver is down, `crictl` + `journalctl -u kubelet` are your only eyes on the node.

---

## To review

- [ ] Redo the upgrade lab from scratch without notes (order: kubeadm pkg → plan → apply → drain → kubelet/kubectl → daemon-reload/restart → uncordon)
- [ ] Redo the etcd backup/restore lab, finding the cert flags from `etcd.yaml` without help
- [ ] Look at an external etcd setup (restore with `--endpoints` to a remote etcd, systemd service instead of static pod)
- [ ] Test the stale-cache symptoms after a restore (delete/scale before restarting CM/scheduler)