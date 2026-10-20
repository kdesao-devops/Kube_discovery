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

Day 3 - Sealed Secrets + scheduling
- Install kubeseal utilities [repo](https://github.com/bitnami/sealed-secrets)


### Rule: never copy chart URLs or versions from tutorials

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

**If it still breaks**
`k -n argocd get app <name> -o jsonpath='{.status.conditions}' | jq .`
then `404` means wrong or moved URL, and `version not found` means wrong `targetRevision`.

