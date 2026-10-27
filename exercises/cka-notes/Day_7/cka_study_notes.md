# ☸️ Kubernetes Certified Administrator (CKA) — Study Notes
## Notes made pretty from the CKA course on Udemy
Covers Section 1 and 2 untill unit 29: Deployement

---

## 📑 Table of Contents
1. [Kubernetes Architecture Overview](#kubernetes-architecture-overview)
2. [Control Plane Components](#control-plane-components)
3. [Worker Node Components](#worker-node-components)
4. [Container Runtimes: Docker vs containerd vs Tools](#container-runtimes-docker-vs-containerd-vs-tools)
5. [Core Workload Resources](#core-workload-resources)
6. [Essential Imperative Commands & Tips](#essential-imperative-commands--tips)

---

## 1. Kubernetes Architecture Overview

Kubernetes follows a client-server architecture split into two main layers:
* **Control Plane Nodes:** The brain of the cluster, responsible for cluster-wide decisions (scheduling, state reconciliation, API interactions).
* **Worker Nodes:** The workhorses that actually execute and maintain container workloads.

```
       +-------------------------------------------------------+
       |                  CONTROL PLANE                        |
       |                                                       |
       |     +------------------+         +---------------+    |
       |     |  kube-scheduler  | <-----> | kube-apiserver|    |
       |     +------------------+         +-------+-------+    |
       |                                          ^            |
       |     +--------------------------+         |            |
       |     | kube-controller-manager  | <-------+            |
       |     +--------------------------+         v            |
       |                                      +-------+        |
       |                                      | etcd  |        |
       |                                      +-------+        |
       +------------------------------------------+------------+
                                                  |
                         +------------------------+------------------------+
                         | (HTTPS / TLS)                                   |
                         v                                                 v
       +----------------------------------+              +----------------------------------+
       |          WORKER NODE 1           |              |          WORKER NODE 2           |
       |                                  |              |                                  |
       |  +----------+     +------------+ |              |  +----------+     +------------+ |
       |  | kubelet  |     | kube-proxy | |              |  | kubelet  |     | kube-proxy | |
       |  +----+-----+     +------------+ |              |  +----+-----+     +------------+ |
       |       |                          |              |       |                          |
       |       v                          |              |       v                          |
       |  [Runtime: containerd / CRI]     |              |  [Runtime: containerd / CRI]     |
       |  +-----------------------------+ |              |  +-----------------------------+ |
       |  |  Pod A         Pod B        | |              |  |  Pod C         Pod D        | |
       |  +-----------------------------+ |              |  +-----------------------------+ |
       +----------------------------------+              +----------------------------------+
```

---

## 2. Control Plane Components

### 2.1 `etcd`
* **Role:** Consistent, highly available key-value datastore (part of the CNCF).
* **Function in K8s:** Acts as the single source of truth for the entire cluster state (nodes, pods, configs, secrets, service accounts, roles, bindings).
* **Structure:** Hierarchical key paths starting at `/` (e.g., `/registry/...`).
* **Deployment:**
  * In `kubeadm`, it runs as a static pod (`/etc/kubernetes/manifests/etcd.yaml`).
  * In custom/hardened clusters, it can be deployed on dedicated external nodes.
* **CLI tool:** `etcdctl` (version 3 API).
  ```bash
  ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /tmp/etcd-backup.db
  ```

---

### 2.2 `kube-apiserver`
* **Role:** Primary central hub of the control plane; the only component that interacts directly with `etcd`.
* **Execution Flow:**
  1. **Authentication:** Checks the caller's identity (certificates, tokens).
  2. **Authorization:** Checks RBAC (Role / ClusterRole permissions).
  3. **Admission Control:** Validates or mutates the object payload.
  4. **Persistence:** Saves and retrieves state to/from `etcd`.
  5. **Orchestration:** Coordinates scheduler, controllers, and worker kubelets.

---

### 2.3 `kube-controller-manager`
* **Role:** Runs continuous control loops (reconciliation) comparing **desired state** (declared in YAML) with **current state** (observed in cluster).
* **Built-in controllers include:**
  * Node Controller (detects unavailable nodes).
  * Replication / ReplicaSet Controller.
  * Deployment, Job, CronJob Controllers.
  * Namespace, Endpoint, ServiceAccount, and PersistentVolume Controllers.

---

### 2.4 `kube-scheduler`
* **Role:** Decides **which worker node** should host a newly created pod.
* **Important distinction:** The scheduler **only assigns** the node (`spec.nodeName`); it **does not** run the pod itself (that is the `kubelet`'s job).
* **Selection Process:**
  1. **Filtering:** Checks resource limits (CPU/RAM), taints/tolerations, node selectors, and affinities.
  2. **Scoring:** Ranks qualifying nodes to find the optimal fit.

---

## 3. Worker Node Components

### 3.1 `kubelet`
* **Role:** The primary node agent running on every worker node.
* **Responsibilities:**
  * Registers the node with the `kube-apiserver`.
  * Watches for assigned PodSpecs and requests the local container runtime (via CRI) to spawn/stop containers.
  * Periodically probes container health (Liveness, Readiness, Startup).
  * Reports status back to the control plane.
* **CKA Note:** `kubelet` is **not** managed as a pod by `kubeadm`; it runs as a host `systemd` service (`systemctl status kubelet`).

---

### 3.2 `kube-proxy`
* **Role:** Network proxy running on each node that implements Kubernetes `Service` abstractions.
* **How it works:**
  * Translates virtual Service ClusterIPs to actual backend Pod IPs.
  * Programs host networking rules (using `iptables` or `IPVS`).
  * Service IPs are virtual abstractions held in network lookup tables/memory, not assigned to physical interfaces.

---

## 4. Container Runtimes: Docker vs containerd vs Tools

```
[ Developer / Admin Tools ]       [ Kubernetes Engine ]
            |                               |
       docker / nerdctl                   kubelet
            |                               |
            v                               v
    (Docker Engine API)             (CRI: Container Runtime Interface)
            |                               |
            +-------------> containerd <----+
                                |
                              runc
                                |
                            [Linux OS: cgroups / namespaces]
```

### Clarifying the Terms
* **Docker:** A full suite/ecosystem (CLI, daemon, builder, volume manager, registry tooling).
* **containerd:** The lightweight, low-level core runtime extracted from Docker to manage image pull, unpack, and container lifecycles.
* **Dockershim Deprecation:** Kubernetes removed native `dockershim` support in v1.24; clusters talk directly to runtimes like `containerd` or `CRI-O` using the standardized **CRI (Container Runtime Interface)**.

### Tool Comparison (Quick Reference)

| Tool | Target Audience | Primary Use Case |
| :--- | :--- | :--- |
| `docker` | Developers | Build, ship, and run images locally. |
| `nerdctl` | Sysadmins / Engineers | Drop-in Docker-compatible CLI for **containerd** (supports Docker Compose, rootless, etc.). |
| `crictl` | CKA Candidates / SREs | CLI designed specifically for Kubernetes **CRI debugging** on worker nodes (inspecting pods, image caches, runtime errors). |

```bash
# Debugging runtime on worker nodes:
crictl pods
crictl ps
crictl logs <container-id>
```

---

## 5. Core Workload Resources

### 5.1 Pods
* Smallest deployable unit in Kubernetes.
* Encapsulates one or more containers sharing:
  * **Network namespace:** Pods share an IP and can communicate via `localhost`.
  * **Storage volumes:** Mounted volumes can be accessed across containers in the pod.
* **Multi-container pattern rule of thumb:** Only combine multiple containers inside one pod if they share a tight lifecycle dependency (e.g., Sidecar, InitContainer, Ambassador, Adapter). **Scale horizontally by adding pods, not by adding containers.**

---

### 5.2 Deployments
* High-level abstraction built on top of **ReplicaSets**.
* Provides declarative declarative lifecycle management:
  * Zero-downtime rolling updates.
  * Instant rollbacks (`kubectl rollout undo`).
  * Pausing and resuming rollout changes.
  * Desired replica count maintenance.

---

## 6. Essential Imperative Commands & Tips

### Fast YAML Generation (`--dry-run=client -o yaml`)
Never write manifests from scratch during the exam:

```bash
# Generate a Pod manifest
kubectl run redis --image=redis:alpine --dry-run=client -o yaml > pod.yaml

# Generate a Deployment manifest with 3 replicas
kubectl create deployment web-app --image=nginx:alpine --replicas=3 --dry-run=client -o yaml > deploy.yaml

# Apply configuration
kubectl apply -f pod.yaml
```

---

### Mass Deletion & Pod Selection (Wildcard Alternatives)
`kubectl` does **not** interpret wildcards (e.g., `kubectl delete pods/app-*` fails with `NotFound`). Use labels or pipes:

```bash
# 1. Preferred CKA method: By Label Selector
kubectl get pods --show-labels
kubectl delete pods -l app=nginx

# 2. Delete all pods managed by a specific ReplicaSet hash
kubectl delete pods -l pod-template-hash=5c7477b4f8

# 3. Shell pipe fallback when names share a prefix without common labels
kubectl get pods --no-headers -o custom-columns=":metadata.name" \
  | grep '^new-replica-set-' \
  | xargs kubectl delete pod
```