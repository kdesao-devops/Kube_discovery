# CKA Notes - DAY 4

---

## 1. Custom Schedulers & Architecture

The default `kube-scheduler` handles standard pod scheduling based on resource limits, taints, and basic affinity rules. However, custom or secondary schedulers can run alongside it in the same cluster.

> **Why Custom Schedulers?**
> * **Advanced / Non-standard placement:** Routing via external telemetry (GPU topology/NVLink, latency, dynamic spot prices).
> * **Batch & AI/ML (Gang scheduling):** "All-or-nothing" scheduling (Volcano, Kueue) to prevent distributed job deadlocks.
> * **Multi-tenancy & Queuing:** Fair-share algorithms, departmental quotas, and queue prioritization across teams.
> * **Side-by-side execution:** Run alongside `default-scheduler` using `spec.schedulerName: <custom-name>` in Pod specs.

### Scheduling Phases & Framework
The scheduling lifecycle follows 4 main steps, driven by internal plugins:
1. **Queuing:** Pods enter the scheduling queue sorted by priority.
2. **Filtering (Predicates):** Filters out nodes that cannot satisfy the pod requirements (resources, taints, nodeSelector).
3. **Scoring (Priorities):** Assigns a score to surviving nodes to determine the best placement.
4. **Binding:** Writes the node assignment binding into `etcd` via `kube-apiserver`.

*Note on Scheduler Profiles:* Multiple scheduler profiles can be configured inside a single binary by tuning which plugins are enabled/disabled per profile name.

### Config Pattern: In-Cluster Configuration via ConfigMap
Instead of manually copying configuration files onto control plane nodes, you can embed the entire YAML configuration inside a `ConfigMap` string and mount it as a volume directly into the scheduler pod.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-scheduler-config
  namespace: kube-system
data:
  my-scheduler-config.yaml: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    profiles:
      - schedulerName: my-scheduler
    leaderElection:
      leaderElect: false
```

---

## 2. RBAC Requirements for Custom Schedulers

A custom scheduler acts as a robot/machine component running inside the cluster. To discover nodes and bind pods without permission errors, it requires dedicated RBAC objects:

1. **`ServiceAccount` (`my-scheduler`)**: The service identity under which the scheduler pod runs.
2. **`ClusterRoleBinding` (`my-scheduler-as-kube-scheduler`)**: Binds the native cluster role `system:kube-scheduler` to inspect pods/nodes and issue `Binding` resources.
3. **`ClusterRoleBinding` (`my-scheduler-as-volume-scheduler`)**: Grants rights to inspect PVC/PV storage topologies so pods aren't scheduled onto nodes disconnected from required persistent volumes.

*(Analogy: In AWS IAM, the `ServiceAccount` is the machine IAM Role / IRSA, while the two `ClusterRoleBindings` act as Managed Policies attached to that role).*

---

## 3. LAB - Custom Scheduler Operations

```bash
# Switch default context namespace to kube-system
kubectl config set-context --current --namespace=kube-system

# Inspect the default control plane scheduler
kubectl describe pods kube-scheduler-controlplane -n kube-system

# Check the custom scheduler ServiceAccount
kubectl get serviceaccount my-scheduler -n kube-system

# Troubleshoot scheduler events and pod placement
kubectl get events -o wide --sort-by='.metadata.creationTimestamp'
kubectl logs -n kube-system <my-scheduler-pod-name>
```

To schedule a Pod using the secondary scheduler:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-scheduled-app
spec:
  schedulerName: my-scheduler
  containers:
  - name: nginx
    image: nginx
```

---

## 4. Admission Controllers

Admission controllers intercept incoming requests to the `kube-apiserver` **after** authentication and authorization (RBAC) are verified, but **before** objects are written to `etcd`.

* **Mutating Admission Controllers:** Can modify or mutate the incoming object before validation (e.g., injecting sidecar containers, enforcing storage classes, defaulting parameters).
* **Validating Admission Controllers:** Check the object against organizational policies and reject the request with an error if rules are violated (e.g., preventing containers from running as root, forbidding `:latest` image tags).

### Key Commands & Manifests
```bash
# List all built-in admission plugins supported by kube-apiserver
kube-apiserver -h | grep enable-admission-plugins

# Edit control plane manifests (kubelet monitors this path via static pods)
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

> **Note on Static Pod Manifests:** Changes made to files in `/etc/kubernetes/manifests/` are continuously watched by the local `kubelet` daemon and automatically redeployed.

---

## 5. Dynamic Admission Control (Webhooks)

Admission controllers can be extended dynamically via HTTP callbacks without recompiling or restarting `kube-apiserver`:

1. **`ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration`**: Registers external endpoints with URL paths, rules, and a CA bundle (`caBundle`).
2. **Webhook Backend Server**: An external service (often written in Go) that receives an `AdmissionReview` payload, validates or mutates the container spec, and returns an admission decision.

### Example Rejection Message
When a policy blocks an action, the API server rejects the client request:
```text
Error from server (Forbidden): error when creating "/root/test-deploy.yaml": 
pods "test-deploy" is forbidden: image policy webhook backend denied one or more images: 
Images using latest tag are not allowed
```

### LAB - Admission Controller TLS Setup

Dynamic webhooks require strictly valid TLS certificates. `kube-apiserver` will refuse unencrypted or unauthenticated webhook traffic.

```bash
# Create the TLS Secret containing the certificate and private key for the webhook server
kubectl create secret tls webhook-server-tls \
  --cert=/root/keys/webhook-server-tls.crt \
  --key=/root/keys/webhook-server-tls.key \
  -n webhook-demo
```