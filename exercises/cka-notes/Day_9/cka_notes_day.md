# CKA Notes - DAY 3

---

## 1. Scheduling & Manual Scheduling

A pod can be scheduled without any running scheduler by specifying the `nodeName` attribute directly in the pod manifest.
`kubectl apply` will fail on a running pod when modifying this field because `spec.nodeName` is immutable. 
You must use `--force` (or replace) if the pod already exists.

### LAB - Manual Scheduling

```bash
# Check scheduler availability in the cluster
kubectl get pods --namespace kube-system

# Inspect pod spec for node-related fields
kubectl explain pods.spec --recursive | grep --context=10 node
```

> **Note : Immutabilité du Pod & Manual Scheduling**
> * **Erreur `Forbidden` :** Un Pod existant est quasi-immutable ; on ne peut pas modifier `spec.nodeName` à chaud avec un simple `kubectl apply`.
> * **Remplacement forcé :** Utiliser `kubectl replace --force -f <file>.yaml` ou `kubectl apply -f <file>.yaml --force` (supprime et recrée le Pod).
> * **Alternative Pod `Pending` :** Utiliser un objet `Binding` envoyé à l'API du Pod pour l'assigner manuellement sans le détruire.

```bash
# Inspect nodes placement
kubectl get pods -o wide

# Count pods filtered by label
kubectl get pods -l 'env=dev' -o wide | wc -l          # Remove 1 manually for header
kubectl get pods -l 'bu=finance' --no-headers | wc -l  # Clean count without header

# Multi-label filtering (logical AND)
kubectl get all -l 'env=prod' -o wide
kubectl get pods --selector='env=prod,bu=finance,tier=frontend'
kubectl get pods -l env=dev,bu=finance,tier=frontend
```

---

## 2. Taints and Tolerations

* By default, pods have no tolerations, preventing them from being scheduled on tainted nodes.
* **Taints** are set on **Nodes**.
* **Tolerations** are set on **Pods**.
* Master/Control-plane nodes have a default `NoSchedule` taint to prevent regular workloads from running on them.

### Effects of Taints
* `NoSchedule`: Hard constraint; pods without toleration will not be scheduled on the node.
* `PreferNoSchedule`: Soft constraint; the system avoids placing pods on the node if possible.
* `NoExecute`: Affects running pods; non-tolerant pods currently executing on the node are evicted.

### LAB - Taints and Tolerations

```bash
# Retrieve taints of a specific node
kubectl get node node01 -o jsonpath='{.spec.taints}'
kubectl get nodes node01 -o custom-columns="TAINTS:.spec.taints[*].key,EFFECT:.spec.taints[*].effect"

# Apply a taint to a worker node
kubectl taint node node01 spray=mortein:NoSchedule

# Remove a taint (note the trailing '-')
kubectl taint node controlplane node-role.kubernetes.io/control-plane:NoSchedule-

# Explore tolerations schema (remember: tolerations is a YAML array [])
kubectl explain pods.spec.tolerations
```

#### Pod Toleration Syntax (Array)
```yaml
spec:
  tolerations:
  - key: "spray"
    operator: "Equal"
    value: "mortein"
    effect: "NoSchedule"
```

---

## 3. Node Selection & Node Affinity

* **NodeSelector**: Simple, mandatory (`key: value`) label matching for scheduling.
* **NodeAffinity**: Advanced and expressive node matching rules supporting operators (`In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`).

### LAB - Node Affinity

```bash
# Inspect labels on a node
kubectl describe node node01 | grep -i -C 5 "labels"

# Add a label to a node
kubectl label nodes node01 color=blue

# Generate deployment skeleton
kubectl create deployment blue --image=nginx --replicas=3 --dry-run=client -o yaml > blue.yaml
```

#### Syntax Reference (Hard Affinity)
> **Watch out :**
> * Use `matchExpressions` (for arbitrary node labels), NOT `matchFields` (reserved for internal fields like `metadata.name`).
> * Operators are case-sensitive (`In`, `NotIn`, `Exists`).
> * `values` must be an array (list).

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: color
            operator: In
            values:
            - blue
```

---

## 4. Resource Management (Requests & Limits)

* **CPU**: Throttled when exceeding its limit (compressible resource).
* **Memory**: Incompressible resource; pods exceeding limits face OOM (Out Of Memory) kill termination.
* **Default behavior**: No requests, no limits.
* **Requests only**: Guarantees baseline capacity while still allowing the container to consume unallocated node resources.
* **LimitRanges**: Enforce default requests/limits at namespace scope; applies **only to newly created pods**, never retroactively to running pods.

### LAB - Resources

```bash
# Extract existing pod specification
kubectl get pod elephant -o yaml > elephant.yaml

# Recreate the pod with updated resource limits
kubectl replace --force -f elephant.yaml
```

---

## 5. DaemonSets

* Ensures one copy of a pod runs on all (or targeted) nodes automatically.
* Adds pods on newly joined nodes and cleans them up upon node removal.
* Typical use cases: cluster logging (`fluentd`), node monitoring, network plugins (`calico`, `flannel`), and `kube-proxy`.
* Spec is structurally identical to a Deployment / ReplicaSet without `replicas` or `strategy`.

### LAB - DaemonSet

```bash
# Inspect existing DaemonSets
kubectl describe pods kube-flannel-ds-wxz76 -n kube-flannel
kubectl describe ds kube-flannel-ds -n kube-system

# Fast workflow: craft a DaemonSet from a Deployment skeleton
kubectl create deploy elasticsearch --image="registry.k8s.io/fluentd-elasticsearch:1.20" -n kube-system --dry-run=client -o yaml > FluentD.yaml
```

**Edits to apply on `FluentD.yaml` :**
1. Change `kind: Deployment` to `kind: DaemonSet`
2. Ensure `apiVersion: apps/v1`
3. Delete `spec.replicas` and `spec.strategy`
4. Apply: `kubectl apply -f FluentD.yaml`

---

## 6. Static Pods

* Managed directly by the local `kubelet` daemon without `kube-apiserver` supervision.
* Defined via YAML manifests placed in the kubelet's manifest directory (often `/etc/kubernetes/manifests`).
* Standard mechanism used by `kubeadm` to bootstrap control plane components (`etcd`, `apiserver`, `controller-manager`, `scheduler`).

```bash
# Check the staticPodPath configuration in kubelet
cat /var/lib/kubelet/config.yaml | grep -i staticpodpath

# Generate a static pod manifest directly into the target directory
kubectl run static-busybox --image=busybox -n default --dry-run=client -o yaml --command -- sleep 1000 > /etc/kubernetes/manifests/static-busybox.yaml
```

---

## 7. Pod Priority & Preemption

* **PriorityClasses** define the relative priority of pods for scheduling.
* If a high-priority pod cannot be scheduled due to insufficient resources, the scheduler can trigger **preemption**, terminating lower-priority pods to release capacity.

### LAB - Priorities & PriorityClass

```bash
# Vérifier les PriorityClasses existantes dans le cluster
kubectl get priorityclasses.scheduling.k8s.io

apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 100000
description: "lab priority policy"
preemptionPolicy: "PreemptLowerPriority"
globalDefault: false

# Déployer la PriorityClass (préférer apply pour les annotations déclaratives)
kubectl apply -f PriorityClass.yaml

# Vérifier la priorité affectée aux pods
kubectl get pods -o custom-columns="NAME:.metadata.name,PRIORITY:.spec.priorityClassName"

# Assigner la PriorityClass à un pod existant (nécessite recréation)
kubectl get pod critical-app -o yaml > critical-app.yaml
# Dans critical-app.yaml : 
# 1. Supprimer le champ live 'priority: 0' (généré par le cluster)
# 2. Ajouter sous spec : priorityClassName: high-priority
# 3. Supprimer et recréer le pod :
kubectl replace --force -f critical-app.yaml
```