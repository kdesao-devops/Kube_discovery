Ce qu’on attend de toi (45 min)

Dans un namespace dédié sched, tu manipules les mécanismes qui décident où atterrit un pod, puis tu apprends à diagnostiquer quand ça ne marche pas.

- a nodeSelector : labelliser un agent (disk=ssd), créer un pod qui ne va que sur ce nœud, vérifier avec -o wide.

- b Taint / toleration : tainter un agent (dedicated=gpu:NoSchedule), constater qu’un pod normal l’évite, créer un pod avec la toleration correspondante, retirer le taint (tiret final). Comparer NoSchedule, PreferNoSchedule et NoExecute sur un pod déjà en cours.

- c Affinity : écrire un pod avec nodeAffinity (required), puis un Deployment à 3 réplicas avec podAntiAffinity pour les étaler sur les nœuds. Tu dois savoir retrouver l’exemple dans la doc officielle.

- d Cordon / drain : cordon, drain (--ignore-daemonsets --delete-emptydir-data) puis uncordon sur un agent uniquement. Observer où partent les pods (ArgoCD notamment) et vérifier que podinfo reste accessible.

- e Pod Pending : poser un nodeSelector impossible (disk=nvme) et lire le message FailedScheduling dans describe pod (Events).

À éviter : les static pods (K3s ne se comporte pas comme kubeadm).

Livrables
Tes temps, erreurs et ce que tu as dû chercher dans exercises/cka-notes/scheduling.md
Nettoyage : k delete ns sched et retour au namespace default
Le vrai objectif

Pouvoir faire tout ça sans copier-coller : tu génères le YAML avec $do, tu n’ajoutes que le bloc manquant, et tu vérifies. C’est le réflexe d’examen CKA : vitesse, k explain, navigation dans la doc.

Critère de réussite pour cette partie

Avoir posé un taint, une toleration, un nodeSelector et drainé un nœud, tout ça de mémoire (hors YAML d’affinity que tu as le droit de chercher dans la doc).