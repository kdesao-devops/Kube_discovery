# CKA Study Notes — DAY 2

## Services

Facilitate communication between users, frontend, backend, and database. In other words, facilitate network connectivity between the outside and the inside of the Kubernetes cluster.

### Types of Services

* **NodePort**:
  * Acts similarly to NAT.
  * Involves 3 ports:
    * **NodePort**: Port exposed on the host node (`30000-32767`).
    * **Port**: Port exposed on the Service object itself.
    * **TargetPort**: Port exposed by the actual container inside the Pod.
  * Automatically balances traffic across multiple Pods within the same node or across multiple nodes, functioning like an internal load balancer (using random selection + session affinity).
  * Uses label selectors to match target Pods.
  * *Limitation*: Exposes the IP of each individual node; not suitable for direct end-user access.
* **ClusterIP (Default)**:
  * Facilitates internal communication between Pods inside the cluster.
  * Assigns a stable internal cluster IP and DNS name (`<service-name>.<namespace>.svc.cluster.local`) pointing to Pods matching the selector.
* **LoadBalancer (Cloud Only)**:
  * Handles outside-to-inside communication on supported cloud providers (AWS, GCP, Azure).
  * Unlike NodePort (which leaves multiple node IPs exposed), LoadBalancer provisions a single external entry-point IP.

### LAB - Services

```bash
# Imperatively create a NodePort service
kubectl create service nodeport webapp-service --node-port=30080 --tcp='8080:8080'

# Force replace an existing service configuration
kubectl replace --force -f service.yaml
```

---

## Namespaces

Virtual allocation of isolated environments within the same physical cluster. Used to organize environments (dev, test, prod) and enforce resource quotas (CPU, RAM).

### LAB - Namespaces

```bash
# Create a pod inside a dedicated namespace
kubectl run redis --image=redis -n finance

# List pods across all namespaces
kubectl get pods --all-namespaces
```

---

## Imperative vs Declarative

* **Imperative**: Explicit, step-by-step instructions telling the system *how* to do something (e.g., turn right, go straight, turn left, arrive at Tom's place).
* **Declarative**: Specifies the desired end state (e.g., go to Tom's place, arrive).
* **Live Object Configuration**: The active internal state of an object stored in `etcd` by Kubernetes.
* **Key Mechanism**: `kubectl apply` adds the `last-applied-configuration` annotation to the live object. Stick to `apply` or stick to imperative commands—avoid mixing both on the same resources.
* `kubectl apply -f <file.yaml>` intelligently reconciles and updates the live object to match the YAML definition without needing `kubectl replace --force`.

---

## kubectl explain (Crucial for CKA)

Inspect API resource specifications directly from the terminal without leaving the exam environment:

```bash
# General summary of the resource
kubectl explain pods

# Detailed view of spec fields and child attributes
kubectl explain pods.spec

# Full recursive schema tree (best way to see manifest hierarchy)
kubectl explain pods --recursive
```

---

## LAB - Imperative Commands

```bash
# Pod generation
kubectl run nginx-pod --image=nginx:alpine
kubectl run redis --image=redis:alpine -l 'tier=db'
kubectl run custom-nginx --image=nginx --port=8080

# Service manifest generation & application
kubectl create service clusterip redis-service --dry-run=client --tcp=6379:6379 -o yaml
# -> Update YAML selector if necessary to match 'tier=db', then apply:
kubectl apply -f svc.yaml

# Deployments & Namespaces
kubectl create deployment webapp --image=kodekloud/webapp-color --replicas=3 -o yaml
kubectl create ns dev-ns -o yaml
kubectl create deploy redis-deploy --namespace=dev-ns --image=redis --replicas=2 -o yaml

# Run a pod and automatically expose it with a service
kubectl run httpd --image=httpd:alpine --expose
```