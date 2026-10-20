helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm search repo argo/argo-cd --versions | head -5
helm show values argo/argo-cd --version <VERSION> > /tmp/argocd-defaults.yaml

helm install argocd argo/argo-cd --version <VERSION> \
  -n argocd --create-namespace \
  -f gitops/platform/argocd/values.yaml

k -n argocd get pods -w
k -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

k apply -f gitops/bootstrap/root.yaml
k -n argocd get applications -w