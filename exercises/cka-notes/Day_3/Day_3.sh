k create ns sched    # Create a namespace called sched
k config set-context --current --namespace=sched     # Set the current context to the sched namespace

k get nodes                      # repère le nom d'un agent (pas le server)
k label node k3d-lab-agent-0 disk=ssd
k get nodes --show-labels | grep disk   # vérifie que le label est posé
k run p1 --image=nginx $do > p1.yaml

k apply -f p1.yaml
k get pod p1 -o wide             # colonne NODE : il doit être sur ton agent

k taint node k3d-lab-agent-0 dedicated=gpu:NoSchedule
k run p2 --image=nginx

k run p3 --image=nginx $do > p3.yaml
k apply -f p3.yaml

k taint node k3d-lab-agent-0 dedicated=gpu:NoSchedule-      # le - supprime le taint
k taint node k3d-lab-server-0 dedicated=gpu:PreferNoSchedule
k taint node k3d-lab-server-0 dedicated=gpu:NoExecute
k taint node k3d-lab-server-0 node-role.kubernetes.io/control-plane:NoSchedule  # Inutile en exam (par defaut) ici c'est pour supprimer l'execution de pod sur le server

k describe node k3d-lab-server-0 | grep -i taint

k run p4 --image=nginx
k get pod p4 -o wide                                  # note sur quel nœud il est
k taint node <ce-nœud> test=1:NoSchedule              # p4 ne bouge pas
k taint node <ce-nœud> test=1:NoExecute               # p4 est tué
k get pods -w                                         # (un pod nu n'est PAS recréé)

k create deploy web --image=ngninx --replicas=3 $do > exercises/cka-notes/Day_3/web.yaml
k apply -f web.yaml

k cordon <agent>
k get nodes                       # statut : Ready,SchedulingDisabled
k drain <agent> --ignore-daemonsets --delete-emptydir-data
k uncordon k3d-lab-agent-0

k run p5 --image=nginx $do > p5.yaml
# ajoute nodeSelector: {disk: nvme}  (ce label n'existe sur aucun nœud)
k apply -f p5.yaml
k get pod p5                       # Pending
k describe pod p5                  # descends tout en bas, section Events
# Modife le deployement yaml {disk: nvme} > {disk: ssd} -> Paf apparition sur k3d-lab-agent-0