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
