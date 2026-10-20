brew install kubeseal
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets && helm repo update
helm search repo sealed-secrets/sealed-secrets --versions | head -3   # note CHART VERSION

