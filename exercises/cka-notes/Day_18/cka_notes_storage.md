# Day 12 — Storage

## Docker storage

### File system — `/var/lib/docker`

| Folder | Content |
|---|---|
| `aufs/` / `overlay2/` | layers of images and containers, one folder per storage driver (overlay2 on modern installs) |
| `containers/` | containers information |
| `image/` | docker images |
| `volumes/` | data of Docker volumes |

### Image layer vs container layer

- **Image layer**: read only, nothing from the image layers can be changed.
- **Container layer**: read + write. When touching files from the image layers at run time, Docker copies the file to the container layer in the background (**copy on write**).
- The container layer is deleted on container deletion.
- Build cache: a `RUN apt-get update` layer is reused as long as the command line doesn't change → packages usually get refreshed only when the base image is updated in CI, unless the team schedules rebuilds.

### Docker persistent storage

| Type | Effect |
|---|---|
| **Bind mount** | Mount a specific location from the host into the container |
| **Volume mount** | Mount a volume for container usage, stored in `/var/lib/docker/volumes/` |

```bash
docker volume create data_volume
docker run -v data_volume:/var/lib/mysql mysql                                 # volume mount
docker run --mount type=bind,source=/data/mysql,target=/var/lib/mysql mysql    # bind mount: absolute paths only (no ~)
```

### Storage drivers

Implement the layered architecture: stack the read-only image layers + the writable container layer, and handle copy on write. Chosen automatically depending on the OS.

```bash
docker info | grep "Storage Driver"
```

| Driver | Note |
|---|---|
| **overlay2** | default today on all Linux distros |
| aufs | old Ubuntu default, removed from Docker |
| devicemapper | old RHEL/CentOS default, removed from Docker |
| btrfs / zfs | only if the host filesystem is btrfs / zfs |
| vfs | no copy on write, full copy of each layer (testing only) |

Kubernetes: containerd does the same job with "snapshotters" (overlayfs by default), data in `/var/lib/containerd`.

---

## Volume driver vs CSI

| | |
|---|---|
| **Volume driver** | Docker-only plugin API to use external volume providers (e.g. RexRay for AWS EBS, abandoned) |
| **CSI** (Container Storage Interface) | Open standard (gRPC) for storage drivers, shared by Kubernetes and other orchestrators. The vendor ships the driver outside K8s code (e.g. `ebs.csi.aws.com`), referenced in `StorageClass.provisioner`. Same idea as CRI (runtime) and CNI (network). |
| **TopoLVM** | CSI driver that dynamically provisions LVs from a local VG on each node (local storage, node-bound), supports online volume expansion |

---

## Persistent volume vs persistent volume claim

| | |
|---|---|
| **Persistent volume (PV)** | Cluster-wide storage resource, created by the admin (static) or by a provisioner via a StorageClass (dynamic) |
| **Persistent volume claim (PVC)** | Namespaced request (size, access mode, storage class); K8s binds it to a matching PV (1:1) |
| **Pod → PVC → PV** | The pod references the PVC (`claimName`), never the PV directly |

- **Binding criteria**: `accessModes` offered by the PV, same `storageClassName`, PV capacity ≥ request (+ optional `selector` on PV labels).
- **Static provisioning**: a PVC requesting 500Mi bound to a 2Gi PV gets the whole 2Gi, the remaining 1.5Gi can't be used by another PVC. With dynamic provisioning the PV is created at the requested size.
- **Access modes**: `RWO` ReadWriteOnce (one node) · `ROX` ReadOnlyMany (many nodes, read only) · `RWX` ReadWriteMany (many nodes) · `RWOP` ReadWriteOncePod (one pod).
- **`volumeBindingMode`** (StorageClass): `Immediate` = PV created/bound as soon as the PVC exists · `WaitForFirstConsumer` = waits for a pod using the PVC to be scheduled (volume in the right node/AZ). With `local-path`, a PVC stays `Pending` until a pod uses it: normal.

```text
Pod                                              Cluster
volumeMounts:                volumes:
- name: log    ──name──→    - name: log
  mountPath: /log             persistentVolumeClaim:
                                claimName: claim-log-1 ──name──→ PVC claim-log-1
                                                                   │ binding: accessModes,
                                                                   │ storageClassName, size
                                                                   ↓
                                                                 PV pv-log (hostPath: /pv/log)
```

---

## LAB — CSI volume storage (TopoLVM)

Manifests: [`cka_storage_lab_csi.yaml`](cka_storage_lab_csi.yaml) (PVC `lab-data` + pod `lab-app`)

```bash
lsblk                                  # tree of block devices (disks, partitions, LVs)
pvcreate /dev/vdd                      # initialize the disk as a Physical Volume (PV)
vgcreate topolvm-vg /dev/vdd           # create a Volume Group (VG) named topolvm-vg from that PV
```

Verification:

```text
pvs
  PV         VG         Fmt  Attr PSize  PFree
  /dev/vdd   topolvm-vg lvm2 a--  <2.00g <2.00g

vgs
  VG         #PV #LV #SN Attr   VSize  VFree
  topolvm-vg   1   0   0 wz--n- <2.00g <2.00g
```

```bash
k label namespaces kube-system topolvm.io/webhook=ignore --overwrite   # exclude the ns from TopoLVM's webhook, otherwise its pods are blocked while the webhook isn't up (chicken-and-egg at install)

helm repo add topolvm https://topolvm.github.io/topolvm
helm repo update                       # refresh the local chart index of all repos
helm repo list

helm install topolvm topolvm/topolvm --version 17.2.0 --namespace topolvm-system --create-namespace --values /root/topolvm-values.yaml

helm list -A                           # Helm releases are namespaced: always pass -n

kubectl get pod -n topolvm-system -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'   # list the containers set by the helm chart
```

> Pitfall: `helm install` without `-n` → release in `default`. Reinstalling in another ns then fails with `invalid ownership metadata` (cluster-scoped objects like the PriorityClass already belong to the first release). Fix: `helm uninstall topolvm -n default` (release name, not chart).

```bash
k apply -f cka_storage_lab_csi.yaml
kubectl get pvc lab-data               # verify
kubectl wait --for=condition=Ready pod/lab-app --timeout=180s

kubectl exec lab-app -- df -h /data
kubectl exec lab-app -- sh -c 'dd if=/dev/urandom of=/data/payload bs=1M count=200'
kubectl exec lab-app -- sh -c 'cd /data && md5sum payload > checksum.txt'

kubectl patch pvc lab-data -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'   # topolvm takes care of disk and fs resize
kubectl logs -n topolvm-system -l app.kubernetes.io/component=controller -c csi-resizer --tail=20
```

> Resize requires `allowVolumeExpansion: true` on the StorageClass, and a PVC can only **increase**, never shrink. Check with `k get pvc lab-data` (CAPACITY) and `df -h /data`.

---

## LAB — Persistent volume claim

Manifest: [`cka_storage_lab_pvc.yaml`](cka_storage_lab_pvc.yaml) (PVC `claim-log-1`)

## LAB — Storage class

Manifests: [`cka_storage_lab_storageclass.yaml`](cka_storage_lab_storageclass.yaml) (PVC `local-pvc` + pod `nginx` + StorageClass `delayed-volume-sc`)

---

## To review

- [ ] Retake the practice test CSI volume resize
- [ ] Redo the PVC lab from scratch: PV with hostPath + PVC + pod, check `Bound`
- [ ] Debug a `Pending` PVC: accessModes / storageClassName / size mismatch
- [ ] StorageClass: `local-path` + `WaitForFirstConsumer`, `no-provisioner`
- [ ] Volume expansion: `allowVolumeExpansion`, increase only
- [ ] LVM chain: `pvcreate` → `vgcreate` → `lvcreate` → `mkfs` → `mount`