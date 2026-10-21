# Architectural decision record

## Day One
Choosed Docker desktop for the runtime 
Choosed K3S for capacity reasons and will be passing on EKS after being ocnfortable locally
Installed CLI tools on my new MAC (git, etc)
ran my first kubenertes cluster with podinfo 
Played around through CLI interface before IaC (GitOps, ArgoCD)
Created the CLI_Debut.sh

## Day 2 – ArgoCD and GitOps

- Checked available ArgoCD chart versions with `helm search repo`.
- Wrote `gitops/platform/argocd/values.yaml` (domain, insecure mode, Traefik Ingress).
- Installed ArgoCD manually with Helm (the only component not managed by GitOps yet).
- Created the root Application (`gitops/bootstrap/root.yaml`): Git repo URL + path
  `gitops/apps` + destination (cluster/namespace) + automated sync (prune, selfHeal).
  Applied once with `kubectl apply`: the only manual step.
- Created `gitops/apps/podinfo.yaml`: Helm repo URL + chart + pinned version + value
  overrides (replicas, Ingress on podinfo.localtest.me) + sync policy.
- Result: ArgoCD discovers podinfo through the app-of-apps pattern and deploys it.

**Learned / incident**
- Image comes from the chart's default values (ghcr.io), not from Git.
- `Sync Unknown` on podinfo: wrong `targetRevision`. Diagnosed via
  `.status.conditions` (ComparisonError), fixed by pinning an existing chart version.

## Day 3 - Sealed Secrets + scheduling

### Part 1 Sealed secret
- Install kubeseal utilities [repo](https://github.com/bitnami/sealed-secrets)
#### Rule: never copy chart URLs or versions from tutorials

**Problem**
Tutorials go stale. Two incidents came from copying values instead of reading them:
- podinfo: wrong `targetRevision` (a version that does not exist).
- sealed-secrets: repo URL moved to another GitHub org (404), and `targetRevision`
  set to the **app** version instead of the **chart** version.

**Procedure before writing any Argo CD Application**
1. Add the repo locally:
   `helm repo add <name> <url> && helm repo update`
2. Read the available versions:
   `helm search repo <name>/<chart> --versions | head`
   Use the `CHART VERSION` column, never `APP VERSION`.
3. Read the defaults:
   `helm show values <name>/<chart> --version <v> | less`
   (image registry, fullnameOverride, ingress options)
4. Dry-run the render:
   `helm template test <name>/<chart> --version <v> -f values.yaml | less`
5. Only then write the Application with the verified `repoURL`, `chart`
   and pinned `targetRevision`, and push.

## CKA: Scheduling

In a dedicated namespace: (Exersice realised in 40mn)

1. Generate a Deployment YAML (`k create deploy ... $do`), never write it from scratch.
2. **nodeSelector**: label an agent (`disk=ssd`) and pin pods to it.
3. **Taint / toleration**: taint an agent with an arbitrary `key=value:effect`, then add the matching toleration to the pod spec (`spec.template.spec` for a Deployment). Compare `NoSchedule` vs `NoExecute`.
4. **Node maintenance**: `cordon` -> `drain` -> `uncordon` on one agent.
5. **Troubleshooting**: set an impossible `nodeSelector` (`disk=nvme`) and read the `FailedScheduling` message in `describe pod` (Events).

Key takeaways:
- A bare pod is immutable (recreate with `k replace --force -f`), a Deployment can be edited (rolling update).
- Drain refuses pods without a controller (`--force` to override).

### Isolate the control-plane (k3d)

K3s/k3d does not taint the server, so application pods can land on it. To mimic kubeadm, do this **systematically in local** after creating the cluster:

```bash
k taint node k3d-lab-server-0 node-role.kubernetes.io/control-plane:NoSchedule
```

> Not needed in the exam: kubeadm clusters already have this taint by default.