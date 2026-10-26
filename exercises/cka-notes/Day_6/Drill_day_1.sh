k3d cluster create drill --servers 1 --agents 2 -p "80:80@loadbalancer" -p "443:443@loadbalancer"
kubectl config get-contexts
k create ns drill
k config set-context --current --namespace=drill

k create deployment drillweb --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2 # -> deployment.apps/drillweb created
k expose deployment.apps/drillweb --port=80 --target-port=9898   # create a service

k port-forward services/drillweb 9898:80                        # Active port-forward

k get deployments,rc,pods,svc                                   # Get info on deployments replicacount,pods,service
k get pods -o wide

k delete pod -l app=web 