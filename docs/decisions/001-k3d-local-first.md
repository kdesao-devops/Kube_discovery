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
```
# Versions Helm
helm list -n argocd
helm search repo argo/argo-cd --versions | head -10
```

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

## Day 4 – Keycloak + PostgreSQL via Argo CD

### Réalisé
1. Secrets chiffrés avec kubeseal (keycloak-db, keycloak-admin)
2. PostgreSQL : StatefulSet + volumeClaimTemplates (local-path, 2Gi)
3. Keycloak : Deployment + Service 8080 + Ingress (Traefik)
4. Application Argo CD pointant sur gitops/platform/keycloak

### Concepts à retenir
- Deployment = pods interchangeables / StatefulSet = identité + volume propre
- volumeClaimTemplates : un PVC par réplica, non supprimé avec le StatefulSet
- Probe exécutée par le kubelet sur l'IP du pod (pas via Service/Ingress)
- JDBC : Keycloak est en Java, d'où jdbc:postgresql://<service>:5432/<db>

### Erreurs rencontrées
- Application Argo : path et chart sont exclusifs
- serviceName n'existe pas dans un Deployment
- Le nom du Service doit correspondre à backend.service.name de l'Ingress
- Probe sur le mauvais port (900 au lieu de 9000)

### Commandes de debug
k describe pod / k logs / k get events -n keycloak
k get sealedsecret,secret -n keycloak

### À revoir
- [ ] Écrire un StatefulSet + PVC de mémoire
- [ ] Créer un Secret et le monter en env et en volume

## Day 5 Connexion à ArgoCD via OIDC avec Keycloak + config via Terraform

### Réalisé
1. Install Terraform + création de la config nécessaire à l'OIDC (client `argocd`, client scope `groups`, mapper Group Membership)
2. Configuration d'ArgoCD pour l'OIDC via Keycloak (`oidc.config` dans les values Helm)
3. Configuration de la RBAC policy : mapping groupe Keycloak → rôle ArgoCD
4. Rewrite CoreDNS pour que les pods résolvent `keycloak.localtest.me` vers Traefik
5. Test de la connexion et des autorisations avec différents utilisateurs

### Concepts à retenir
- **Keycloak dit qui est qui, ArgoCD décide des droits.** Keycloak met `"groups": [...]` dans le token, ArgoCD fait le lien avec ses rôles (`g, platform-admins, role:admin`).
- Le nom du groupe doit matcher exactement (casse incluse) : d'où `full_path = false`.
- **Client scope Default vs Optional** : Default = toujours dans le token, Optional = seulement si l'appli le demande dans `scope`.
- Créer un scope ≠ l'assigner à un client : deux ressources Terraform distinctes.
- Les ressources `*_default_scopes` sont **autoritaires** : elles remplacent toute la liste, il faut relister les scopes standards.
- Le logout ArgoCD ne ferme **que** la session ArgoCD, la session Keycloak reste ouverte (SSO), sauf si on configure `logoutURL`.
- Dans un pod, `localtest.me` → `127.0.0.1` pointe sur le pod lui-même, d'où le rewrite CoreDNS.

### Erreurs rencontrées
- **YAML values mal indenté** : `server.insecure` n'était pas sous `configs.params`.
- **`invalid_scope`** : le scope s'appelait `argocd-client-scope` au lieu de `groups`, donc Keycloak ne le reconnaissait pas pour ce client.
- **`failed to verify the token`** : état de login périmé d'une première connexion ratée, réglé en retentant.
- **`redirigé à de trop nombreuses reprises`** : cookies/cache navigateur corrompus après le logout, résolu en navigation privée ou en vidant les cookies.
- `wget: not found` dans le pod ArgoCD : utiliser un pod `busybox` temporaire.

### Commandes de debug
​```bash
# DNS depuis le cluster
k run dns-test --image=busybox:1.36 -it --rm --restart=Never -- nslookup keycloak.localtest.me
k -n kube-system get svc traefik

# Discovery OIDC depuis le cluster
k run http-test --image=busybox:1.36 -it --rm --restart=Never -- \
  wget -qO- -T 3 http://keycloak.localtest.me/realms/lab/.well-known/openid-configuration

# Logs ArgoCD + redémarrage après changement de config
k -n argocd logs deploy/argocd-server --tail=100
k -n argocd rollout restart deploy/argocd-server
​```
Dans l'UI : Keycloak → Clients → argocd → Client scopes → **Evaluate** ; ArgoCD → **User Info** (groupes reçus).

### À revoir
- [ ] Logout complet (`logoutURL` + `valid_post_logout_redirect_uris`) : fait mais pas vraiment validé
- [x] Gestion du Secret `argocd-oidc`
- [ ] Passage au TLS (`rootCA` à rajouter pour la validation du certificat)
- [x] Tester le rôle `developer` (get/sync mais pas Settings)