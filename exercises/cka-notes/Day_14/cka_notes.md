# Day 8 – Multi-container pods, autoscaling & co.

## Multi-container pods

Containers in the same pod **share**:

- **Lifecycle**: created, scheduled and deleted together, always on the same node.
- **Network**: same IP and network namespace, so they talk to each other via `localhost`.
- **Storage**: they can mount the same volumes (the volume must be declared in `spec.volumes` and mounted in each container).

In the YAML, `spec.containers` is an **array**, so a pod can hold several containers.

### Types of multi-container pods

| Type | Declared under | Behavior |
|---|---|---|
| **Co-located** | `spec.containers[]` | Interdependent containers, all started together, no ordering guarantee. |
| **Regular init container** | `spec.initContainers[]` | Runs setup tasks **before** the main app. Init containers run **one after another, in declaration order**; each must complete successfully before the next starts. They exit once done. |
| **Sidecar** (native) | `spec.initContainers[]` + `restartPolicy: Always` | Starts before the main containers like an init container, but **keeps running** alongside the app for the pod's whole life (logging, proxy, sync…). |

### Sidecar example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-example
spec:
  initContainers:
  - name: sidecar-logger
    image: busybox:1.31
    restartPolicy: Always        # this is what makes it a sidecar
    command: ["sh", "-c", "while true; do echo Sidecar running; sleep 10; done"]
  containers:
  - name: main-app
    image: busybox:1.31
    command: ["sh", "-c", "echo Main app starting; sleep 60"]
```

### Lab: Elastic + Kibana stack

```bash
k exec -n elastic-stack app -- cat /log/app.log   # read the app's log file inside the container
k describe pods | grep "Init Containers"          # note: "Init Containers" with a space, not "InitContainers"
k get pods -w                                     # watch for changes live
```

---

## Autoscaling

- **Manual scaling** (`kubectl scale`) works on Deployments, ReplicaSets **and StatefulSets**. It does **not** need metrics-server.

  ```bash
  k scale deployment/flask-web-app --replicas 3
  ```

  Scaling down a StatefulSet removes pods from the highest ordinal first (`web-2`, then `web-1`…); their PVCs are kept.

- ⚠️ **metrics-server is required** for `kubectl top` and for **autoscaling based on CPU/memory** (HPA, VPA).

### HPA – Horizontal Pod Autoscaler

- **Built into Kubernetes**: adds/removes **replicas**.
- Uses metrics-server for CPU/memory, and can be plugged into other sources (Datadog, Dynatrace, Prometheus…) through the custom/external metrics APIs via an adapter.

### VPA – Vertical Pod Autoscaler

- **Not built in**: installed from the GitHub repo (`kubernetes/autoscaler`). Manifests can be applied straight from a URL:

  ```bash
  k apply -f https://github.com/<path>/<file>.yaml
  ```

- Adjusts the **CPU/memory requests** of the pods (instead of the number of replicas).

**Its three components:**

| Component | Role |
|---|---|
| **Recommender** | Reads the metrics, computes recommended requests and writes them in the VPA object's `status`. In mode `Off`, VPA stops here: recommendations only. |
| **Updater** | Evicts pods whose requests are too far from the recommendation (modes `Recreate` / `Auto`). The owning controller (Deployment, ReplicaSet…) recreates them. |
| **Admission controller** | Mutating webhook: when a pod is **created**, it injects the recommended requests. In mode `Initial`, this is the only action (applied at creation, never evicts). |

**Update modes:** `Off` (recommend only) · `Initial` (apply at pod creation only) · `Recreate` / `Auto` (evict and recreate to apply).

See the recommendations (they live in the VPA object, **not in the logs**):

```bash
k get vpa flask-app -o yaml        # look under status.recommendation
k describe vpa flask-app
```

> Don't use HPA and VPA on the **same CPU/memory metric** for one workload: they'd fight each other.

### When to use which

| | Good fit |
|---|---|
| **Horizontal (HPA)** | Stateless services: web apps, microservices, APIs, nginx, queue consumers |
| **Vertical (VPA)** | Stateful or resource-heavy workloads: databases, JVM-based apps, AI/ML workloads |

---

## CRD (CustomResourceDefinition)

Adds your own resource types to the Kubernetes API (with storage, validation, RBAC and kubectl for free). On its own a CRD does nothing: a **controller** must watch the objects and act on them (**CRD + controller = operator**).

```bash
k get crd
```

---

## Eviction vs delete

The eviction API **refuses an eviction** (`429 Too Many Requests`) when it would violate a **PodDisruptionBudget**, i.e. leave too few replicas and cause downtime.
That's why evicting components (e.g. the `system:evictioner` role) only get `create` on `pods/eviction` and **not** `delete` on `pods`: a raw delete would bypass the PDBs.

---

## Tools

- **Skooner**: web dashboard to monitor/explore a Kubernetes cluster.