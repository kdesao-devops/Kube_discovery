# Useful Aliases Kubectl
source <(kubectl completion zsh)
alias k=kubectl
compdef k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"

# create a cluster
k3d cluster create lab --servers 1 --agents 2 \
-p "80:80@loadbalancer" -p "443:443@loadbalancer"       # Create a cluster with 1 server and 2 agents and expose ports 80 and 443 on the loadbalancer

k create ns demo    # Create a namespace called demo
k config set-context --current --namespace=demo     # Set the current context to the demo namespace

k create deployment web --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2    # Create a deployment called web with 2 replicas and the image ghcr.io/stefanprodan/podinfo:6.7.1
k expose deployment web --port=80 --target-port=9898    # Expose the deployment (equivalent à un service ECS) web on port 80 and target port 9898 (of the pods in the deployment)
k port-forward svc/web 9898:80    # Forward the port 9898 to the port 80 of the service web (accessible depuis le navigateur)
k get deploy,rs,pods,svc    # Get the deployment, replica set, pods and services
k get pods -o wide    # Get the pods and show the nodes

# Casser et observer
k delete pod -l app=web                 # qui recrée ? (ReplicaSet)
k scale deployment web --replicas=4   # Scale the deployment web to 4 replicas
k set image deployment/web podinfo=ghcr.io/stefanprodan/podinfo:6.7.0   # Set the image of the deployment web to ghcr.io/stefanprodan/podinfo:6.7.0 downgrade the version of the image
k rollout status deployment/web   # Get the status of the deployment web
k rollout history deployment/web   # Get the history of the deployment web
k get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers    # Get the pods and show the name and the image of the pods
k rollout undo deployment/web   # Undo the deployment web rollback to the previous version of the image 6.7.1
k get deploy,rs -o wide    # Get the deployment and replica set and show the nodes + image of the pods

# Lire, pas deviner
k describe pod <nom-d-un-pod>           # lis la section Events du pod
k logs deploy/web   # Get the logs of the deployment web
k explain deployment.spec.strategy      # alternative à la doc

k create ingress web --rule="web.localtest.me/*=web:80" $do> ingress.yaml # Marche pasCreate an ingress rule for web.localtest.me to the service web on port 80
cat ingress.yaml # Show the ingress rule
k apply -f ingress.yaml # Apply the ingress rule to the cluster
curl -s http://web.localtest.me | jq . # Get the response from the ingress rule web.localtest.me

k get ingress # Get the ingress rules
k get endpoints web # Get the endpoints of the service web

k9s # Open the k9s terminal CLI to navigate in the cluster
k3d cluster delete lab   # Delete the cluster
