### Create an NGINX Pod

```bash
kubectl run nginx --image=nginx
```

---

### Generate POD Manifest YAML file (`-o yaml`). Don't create it (`--dry-run`)

```bash
kubectl run nginx --image=nginx --dry-run=client -o yaml
```

---

### Create a deployment

```bash
kubectl create deployment --image=nginx nginx
```

---

### Generate Deployment YAML file (`-o yaml`). Don't create it (`--dry-run`)

```bash
kubectl create deployment --image=nginx nginx --dry-run=client -o yaml
```

---

### Generate Deployment YAML file (`-o yaml`). Don’t create it (`–dry-run`) and save it to a file

```bash
kubectl create deployment --image=nginx nginx --dry-run=client -o yaml > nginx-deployment.yaml
```

---

### Make necessary changes to the file (for example, adding more replicas) and then create the deployment

```bash
kubectl create -f nginx-deployment.yaml
```

**OR**

In k8s version 1.19+, we can specify the `--replicas` option to create a deployment with 4 replicas:

```bash
kubectl create deployment --image=nginx nginx --replicas=4 --dry-run=client -o yaml > nginx-deployment.yaml
```