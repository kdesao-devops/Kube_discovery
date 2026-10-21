k create ns keycloak --dry-run=client -o yaml | k apply -f -    # le seal a besoin du namespace pour chiffrer, ArgoCD le gérera ensuite

mkdir -p gitops/platform/keycloak


# Create a random password, the pass it to kubeseal
export pw=$(openssl rand -base64 18)
k create secret generic keycloak-admin -n keycloak \
  --from-literal=username=admin \
  --from-literal=password="$pw" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > gitops/platform/keycloak/sealed-admin.yaml

export pw=$(openssl rand -base64 18)
k create secret generic keycloak-db -n keycloak \
  --from-literal=password="$pw" \
  --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
             --controller-namespace kube-system -o yaml \
  > gitops/platform/keycloak/sealed-db.yaml