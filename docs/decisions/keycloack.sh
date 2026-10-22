k create ns keycloak --dry-run=client -o yaml | k apply -f -    # le seal a besoin du namespace pour chiffrer, ArgoCD le gérera ensuite

mkdir -p gitops/platform/keycloak


# Create a random password, the pass it to kubeseal
k create secret generic keycloak-admin -n keycloak \
  --from-literal=username=admin \
  --from-literal=password="$(openssl rand -base64 18)" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > gitops/platform/keycloak/sealed-admin.yaml

k create secret generic keycloak-db -n keycloak \
  --from-literal=password="$(openssl rand -base64 18)" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > gitops/platform/keycloak/sealed-db.yaml

# Get Password
k -n keycloak get secret keycloak-admin -o jsonpath='{.data.password}' | base64 -d; echo

# Get info
k -n keycloak get sealedsecret,secret,pvc,statefulset,deploy,ingress

# Terraform configuration
export TF_VAR_tf_kc_client_secret=""
tfi
tfa

# Create the OIDC connector secret for argoCD and apply
k create secret generic argocd-oidc -n argocd \
  --from-literal=clientSecret='jeHnEVqYYmzlOswArHSG858jfSQrAdQJtRKewa9yeK3tFNlxoLd1yKSO3J76GzXUsTUo7ArrI0mdsZJPVoCGkv' \
  --dry-run=client -o yaml \
  | k label --local -f - app.kubernetes.io/part-of=argocd -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > gitops/platform/argocd/sealed-oidc.yaml

grep -A3 "template" gitops/platform/argocd/sealed-oidc.yaml

k apply -f gitops/platform/argocd/sealed-oidc.yaml

# Change the config to add OIDC + RBAC and restart ArgoCD (Which isn't on GitOps yet)
helm upgrade argocd argo/argo-cd --version 10.10.5 -n argocd \
  -f gitops/platform/argocd/values.yaml
k -n argocd rollout restart deploy/argocd-server