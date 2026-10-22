brew install kubeseal
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets && helm repo update
helm search repo sealed-secrets/sealed-secrets --versions | head -3   # note CHART VERSION

read -rs "pw?Password: "
k create secret generic demo-secret -n podinfo \
  --from-literal=password="$pw" --dry-run=client -o yaml \
  | kubeseal --controller-name sealed-secrets-controller \
    --controller-namespace kube-system -o yaml \
  > gitops/workloads/podinfo-secret.yaml
unset pw

k apply -f gitops/workloads/podinfo-secret.yaml

k -n podinfo get secret argocd-oidc -o jsonpath='{.data.password}' | base64 -d; echo #kebab

k -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-master-key.yaml       # get private key in case of deletion of the cluster