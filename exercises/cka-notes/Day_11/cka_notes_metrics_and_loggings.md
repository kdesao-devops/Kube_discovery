# CKA Notes - DAY 5 : Monitoring & Metrics Architecture + Logging Architecture & Troubleshooting

## 1. Vue d'ensemble du Monitoring dans Kubernetes

* **Pas de solution native complète intégrée :** Kubernetes n'embarque pas de stack de monitoring tout-en-un par défaut.
* **Historique :** **Heapster** était historiquement la solution populaire d'origine, mais il est **déprécié** aujourd'hui.
* **Metrics Server (remplaçant standard) :** 
  * Successeur officiel et allégé de Heapster.
  * **Limite majeure :** Ne stocke les données qu'en mémoire vive (**in-memory only**). Pas d'historique ni de stockage persistant.
* **Monitoring avancé avec stockage/time-series :**
  * *Open-source :* **Prometheus** (standard cloud-native) ou suite **ELK** (Elasticsearch, Logstash, Kibana).
  * *Solutions propriétaires :* **Datadog**, **Dynatrace**, New Relic.

---

## 2. Collecte & Rôles des Composants

L'agent responsable de l'émission des métriques sur chaque nœud est le **kubelet** via son sous-agent intégré **cAdvisor**.

| Composant | Emplacement | Rôle |
|---|---|---|
| **cAdvisor** | Intégré au `kubelet` (chaque nœud) | Collecte locale des métriques cgroups (CPU / RAM). |
| **Metrics Server** | Pod add-on (souvent dans `kube-system`) | Agrégateur in-memory qui scrape les kubelets. |
| **`metrics.k8s.io`** | API Service dans `kube-apiserver` | Endpoint consommé par `kubectl top` et le **HPA** (Horizontal Pod Autoscaler). |

### Pourquoi cAdvisor est intégré mais pas `kubectl top` ?

* **cAdvisor est local :** Embarqué dans chaque `kubelet`, il surveille uniquement les cgroups locaux du nœud.
* **Protection du Control Plane :** Si `kube-apiserver` interrogeait tous les kubelets à chaque appel CLI, le Control Plane risquerait une surcharge / déni de service.
* **Pas de séries temporelles dans `etcd` :** `etcd` stocke l'état désiré du cluster, jamais des métriques éphémères qui changent chaque seconde.
* **Flux de données :**
  $$\text{kubectl top} \longrightarrow \text{kube-apiserver} \xrightarrow{\text{délégation}} \text{Metrics Server (lecture RAM)} \longrightarrow \text{Kubelet / cAdvisor}$$

---

## 3. Déploiement de Metrics Server

* **Dépôt officiel GitHub :** [kubernetes-sigs/metrics-server](https://github.com/kubernetes-sigs/metrics-server)

### Installation directe (one-liner GitHub)

```bash
# Déploiement direct de la dernière release depuis le repo officiel
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Objets déployés sous le capot (RBAC & Service) :
```text
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
```

---

## 4. Cheat Sheet Commandes CKA & Labs

```bash
# Vérifier la présence et le statut du pod metrics-server
kubectl get pods -n kube-system | grep metrics-server

# Vérifier si l'APIService des métriques est enregistrée et active
kubectl get apiservices | grep metrics.k8s.io

# Consulter directement la réponse brute renvoyée par l'API metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes

# Afficher l'usage CPU/RAM des nœuds et des pods
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -n default --sort-by=memory
```

> **Piège classique de Lab / CKA :**
> Si le pod `metrics-server` crashe ou renvoie des erreurs TLS dans les logs (`x509: certificate signed by unknown authority`), éditer le déploiement (`kubectl edit deploy metrics-server -n kube-system`) et ajouter l'argument suivant sous `spec.template.spec.containers[0].args` :
> ```yaml
> - --kubelet-insecure-tls
> ```

# Logging Architecture & Troubleshooting

## 1. Principes de base du Logging Kubernetes

* **Actif par défaut et transparent :** Tout conteneur écrit nativement ses logs sur ses sorties standards (`stdout` descripteur 1, `stderr` descripteur 2).
* **Accès via l'API Server :** Les logs sont interrogés de manière sécurisée par l'utilisateur via le `kube-apiserver` qui relaie l'appel au `kubelet` hébergeant le pod.
* **Syntaxe de base :**
  ```bash
  # Pod à conteneur unique
  kubectl logs <pod-name>

  # Pod multi-conteneurs (spécifier le conteneur cible)
  kubectl logs <pod-name> <container-name>
  # ou avec le flag explicite
  kubectl logs <pod-name> -c <container-name>
  ```

### Exemples pratiques de lab
```bash
# Consulter les logs d'un pod simple
kubectl logs webapp-1

# Consulter un conteneur précis dans un pod multi-conteneurs et filtrer la sortie
kubectl logs webapp-2 simple-webapp | grep USER30
```

---

## 2. Fonctionnement interne sous le capot (In-Depth)

Contrairement aux idées reçues, `kubectl logs` **ne lit ni `journalctl`** (réservé aux services OS / systemd) **ni un fichier log logé à l'intérieur du conteneur**.

### Flux de la requête
```text
[Utilisateur : kubectl logs]
        │
        ▼ (Requête HTTPS : /api/v1/namespaces/<ns>/pods/<pod>/log)
[kube-apiserver]
        │
        ▼ (API Kubelet : port TCP 10250)
[kubelet (Node hôte)]
        │
        ▼ (Lecture directe sur le disque du Node)
[/var/log/pods/<ns>_<pod>_<uid>/<container>/<restart-count>.log]
```

### Comment les logs arrivent sur l'hôte ?
1. L'application écrit sur `stdout` ou `stderr`.
2. Le moteur de conteneur (ex: `containerd-shim` ou `conmon` pour CRI-O) intercepte les flux au niveau des pseudo-terminaux (ptys).
3. Le runtime écrit ces flux au format texte brut CRI sur le disque de la machine hôte :
   * `/var/log/pods/<namespace>_<pod-name>_<pod-UID>/<container-name>/<restart-count>.log`
   * (Liens symboliques : `/var/log/containers/*.log`)
4. **Format d'une ligne CRI standard :**
   ```text
   2026-11-03T16:45:01.123456789Z stdout F [INFO] User session initialized
   ```

---

## 3. Pourquoi `kubectl logs` peut être vide ? (Pièges classiques)

Tous les conteneurs ne sont pas automatiquement bien configurés :

1. **L'application écrit dans un fichier interne :**
   * Si une application écrit dans `/var/log/app.log` au lieu de la console, `kubectl logs` reste vide.
   * *Astuce officielle Nginx :* Rediriger les fichiers vers les terminaux standards dans le Dockerfile :
     ```dockerfile
     RUN ln -sf /dev/stdout /var/log/nginx/access.log \
      && ln -sf /dev/stderr /var/log/nginx/error.log
     ```
2. **Processus détaché / Démonisation (Background) :**
   * Si le conteneur démarre son service avec `service app start` ou `app &`, le processus quitte le PID 1 du conteneur et n'est plus capté par le runtime. Les processus en conteneur doivent obligatoirement s'exécuter au premier plan (**foreground**).
3. **Buffering applicatif :**
   * Certains runtimes (Python, Java, Ruby) tamponnent les logs en RAM. En Python, ajouter systématiquement `PYTHONUNBUFFERED=1` pour vider le flux immédiatement.

---

## 4. Pattern Sidecar pour Logs Applicatifs (Standard CKA)

Si une application legacy est contrainte d'écrire dans un fichier disque, Kubernetes préconise le pattern **Sidecar Container** de streaming :
* Le conteneur principal écrit dans un volume partagé (`emptyDir`).
* Un conteneur secondaire (Sidecar) monte le même volume et lit le fichier en continu vers sa propre sortie standard avec `tail -n+1 -F`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-sidecar-logger
spec:
  volumes:
  - name: log-volume
    emptyDir: {}
  containers:
  # Conteneur Applicatif principal
  - name: legacy-app
    image: busybox
    args: [/bin/sh, -c, 'while true; do echo "$(date) App event" >> /var/log/app.log; sleep 2; done']
    volumeMounts:
    - name: log-volume
      mountPath: /var/log

  # Conteneur Sidecar de Streaming
  - name: stream-sidecar
    image: busybox
    args: [/bin/sh, -c, 'tail -n+1 -F /var/log/app.log']
    volumeMounts:
    - name: log-volume
      mountPath: /var/log
```

---

## 5. Cheat Sheet Commandes CKA

```bash
# 1. Suivre les logs en temps réel (streaming)
kubectl logs -f <pod-name>

# 2. Récupérer les logs du conteneur AVANT son crash (CrashLoopBackOff)
kubectl logs <pod-name> --previous
kubectl logs <pod-name> -c <container-name> -p

# 3. Limiter le nombre de lignes ou remonter dans le temps
kubectl logs <pod-name> --tail=50
kubectl logs <pod-name> --since=10m

# 4. Logs de tous les pods associés à un label
kubectl logs -l app=frontend --tail=20

# 5. Inspection directe de fichiers internes au conteneur (si pas de stdout)
kubectl exec -it <pod-name> -- cat /var/log/app.log
kubectl exec -it <pod-name> -- tail -f /var/log/app.log

# 6. Déboguer le Kubelet ou le runtime (logs système sur les Nodes)
journalctl -u kubelet -n 100 --no-pager
journalctl -u containerd -n 100 --no-pager
```