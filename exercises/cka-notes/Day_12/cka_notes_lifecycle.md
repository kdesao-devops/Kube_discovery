# Application Lifecycle Management — Rollouts, Commands & Arguments

> CKA prep notes — 2026-11-05

---

## 1. Rollouts and versioning (Deployments)

### How it works

- Every change to a Deployment's **pod template** (`spec.template`: image, env, command, resources, labels…) triggers a **rollout** and creates a new **revision**.
- Under the hood, each revision is a **ReplicaSet**: the Deployment creates a new ReplicaSet, scales it up and scales the old one down. Old ReplicaSets are kept (scaled to 0), which is what makes rollback possible.
- ⚠️ Changing `replicas` (scaling) does **not** create a new revision — it only resizes the current ReplicaSet. Only changes under `spec.template` do.

### Commands

```bash
k rollout status  deployment <name>                    # follow a rollout in progress
k rollout history deployment <name>                    # list revisions
k rollout history deployment <name> --revision=2       # details of one revision
k rollout undo    deployment <name>                    # back to the previous revision
k rollout undo    deployment <name> --to-revision=2    # back to a specific revision
```

> The `CHANGE-CAUSE` column of `rollout history` is filled from the `kubernetes.io/change-cause` annotation (`--record` is deprecated):
> ```bash
> k annotate deployment <name> kubernetes.io/change-cause="image v2"
> ```

### Deployment strategies

| Strategy | Behaviour | Downtime |
|---|---|---|
| `Recreate` | Kill all old pods, then start all new ones | Yes |
| `RollingUpdate` *(default)* | Replace pods progressively, a few at a time | No |

RollingUpdate is tuned with `maxSurge` (extra pods allowed above `replicas`) and `maxUnavailable` (pods allowed to be down), both `25%` by default:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
```

### Lab notes

```bash
# Which image is running?
k describe deployment <name> | grep -i image
k get pods -o custom-columns="NAME:.metadata.name,IMAGE:.spec.containers[0].image"

# Which strategy?
k describe deployment <name> | grep StrategyType

# Update the image imperatively
k set image deployment/<name> <container-name>=<image>:<tag>
k set image deployment/frontend simple-webapp=kodekloud/webapp-color:v2

# Or edit live
k edit deployment frontend
```

> ⚠️ `set image` / `edit` change the live object only: the manifest in Git is no longer the source of truth (drift). Fine for the exam, to avoid in a GitOps setup (ArgoCD would revert it anyway).

---

## 2. Commands and arguments

### Docker basics

1. A container exists to run **one process**. When that process ends, the container stops.
   (In Kubernetes, with the default `restartPolicy: Always`, the pod restarts it → `Completed` / `CrashLoopBackOff`.)
2. **`CMD`** = default command/arguments. Anything given after the image name in `docker run` **replaces** it:
   ```bash
   docker run ubuntu-sleeper sleep 10   # replaces CMD
   ```
3. **`ENTRYPOINT`** = the executable that always runs. Arguments given to `docker run` are **appended** to it, not replacing it.
4. **`ENTRYPOINT` + `CMD`** = executable + default arguments, easy to override:
   ```dockerfile
   FROM ubuntu
   ENTRYPOINT ["sleep"]
   CMD ["5"]
   ```
   ```bash
   docker run ubuntu-sleeper       # → sleep 5
   docker run ubuntu-sleeper 10    # → sleep 10
   ```
   Without the `CMD`, `docker run ubuntu-sleeper` fails: `sleep: missing operand`.
5. The entrypoint itself can only be overridden explicitly:
   ```bash
   docker run --entrypoint sleep2.0 ubuntu-sleeper 10
   ```

#### Dockerfile syntax trap

```dockerfile
CMD sleep 5            # ✅ shell form
CMD ["sleep", "5"]     # ✅ exec form (preferred)
CMD ["sleep 5"]        # ❌ looks for an executable literally named "sleep 5"
```

> Use the **exec form** (JSON array) for `ENTRYPOINT` when combining it with `CMD`: with the shell form, `CMD` is ignored.

### Docker → Kubernetes mapping (the naming is *hilarious*)

| Dockerfile | Kubernetes (`spec.containers[]`) | Role |
|---|---|---|
| `ENTRYPOINT` | `command` | The executable |
| `CMD` | `args` | Its arguments |

Yes: Kubernetes `command` = Docker `ENTRYPOINT`, **not** Docker `CMD`.

```yaml
spec:
  containers:
  - name: ubuntu
    image: ubuntu
    command: ["sleep"]
    args: ["5000"]
```

Both YAML list syntaxes are equivalent:

```yaml
command:
  - "sleep"
  - "1200"
# ==
command: ["sleep", "1200"]
```

### Imperative: `kubectl run` with arguments / command

There is **no `--args` flag**. Everything after `--` goes to the container; `--command` decides where it lands:

| Command | Result in the YAML |
|---|---|
| `k run x --image=img -- a b` | `args: [a, b]` (overrides `CMD`) |
| `k run x --image=img --command -- a b` | `command: [a, b]` (overrides `ENTRYPOINT`) |

```bash
# args only (the image's ENTRYPOINT is kept)
k run webapp-green --image=kodekloud/webapp-color -- --color=green

# command + args (ENTRYPOINT replaced)
k run webapp-green --image=kodekloud/webapp-color --command -- python app.py --color=green

# Generate the YAML instead of creating the pod
k run webapp-green --image=kodekloud/webapp-color --dry-run=client -o yaml -- --color=green
```

> ⚠️ `["--color", "green"]` is YAML syntax, not shell syntax. On the command line, items are separated by spaces. In zsh, brackets are a glob → `no matches found`.

---

## 3. Modifying a running Pod (immutable fields)

Most fields of `spec.containers` (e.g. `command`, `args`) are **immutable** on a Pod: you must delete and recreate it.

```bash
k replace --force -f ubuntu-sleeper-3.yaml --grace-period=0
# ==
k delete pod ubuntu-sleeper-3 --now      # --now = 1s grace period
k apply -f ubuntu-sleeper-3.yaml
```

### Why `k apply --force` hangs (`context deadline exceeded`)

On deletion, the kubelet sends **SIGTERM** to the container's main process. Here that is `sleep`, running as **PID 1**. Linux gives PID 1 no default action for SIGTERM, and `sleep` installs no handler, so the signal is ignored. Kubernetes waits the full `terminationGracePeriodSeconds` (30s) before SIGKILL, and `apply` times out first.

Fixes: `--grace-period=0` / `--now`, or for lab pods only:

```yaml
spec:
  terminationGracePeriodSeconds: 0
```

### Exam workflow with no manifest file

```bash
k edit pod <name>
# → immutable field: edit refuses, but saves your version in /tmp/kubectl-edit-XXXX.yaml
k replace --force -f /tmp/kubectl-edit-XXXX.yaml
```

---

## 4. Finding a field: `kubectl explain`

```bash
k explain pod.spec.containers.command        # one field, with its full description
k explain pod.spec.containers --recursive    # field tree of one branch — very useful!
```

> `--recursive` on the whole `pod` is unreadable; scope it to a branch. Field names are **case-sensitive** (`command`, not `Command`).

### `kpath`: find the full path of a field

Add to `~/.zshrc` (or type it at the start of the exam — `awk` is available):

```bash
kpath(){ kubectl explain $1 --recursive|awk -v r=$1 '/^ +[a-zA-Z]/{match($0,/^ */);l=RLENGTH/2;p[l]=$1;s=r;for(i=1;i<=l;i++)s=s"."p[i];print s}'|grep -i "$2";}
```

```
$ kpath pod command
pod.spec.containers.command
pod.spec.ephemeralContainers.command
pod.spec.initContainers.command
pod.spec.containers.lifecycle.postStart.exec.command
pod.spec.containers.livenessProbe.exec.command
...
```

Then `k explain <path>` for the documentation.

> Exam reflex: for common fields, generating YAML with `k run ... --dry-run=client -o yaml` is faster than searching. Keep `explain` / `kpath` for the rest (`securityContext`, `tolerations`, `affinity`, probes…).