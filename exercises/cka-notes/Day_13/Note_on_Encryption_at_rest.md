## Secrets — Encryption at rest (etcd)

### The problem

- A Secret is only **base64-encoded**, not encrypted.
- By default, the kube-apiserver writes it to **etcd in plain text** (provider `identity`) → on **disk**, not just in RAM.
- Anyone with access to etcd (or its backups / snapshots) can read every Secret.
- Other exposure paths (not solved by encryption at rest):
  - RBAC: whoever can `get`/`list` secrets in a namespace reads them
  - Whoever can **create a Pod** in a namespace can mount any Secret of that namespace
- On the nodes, Secrets mounted as volumes live in **tmpfs** (RAM) → never written to the node's disk. That part is fine.

### Check: is it encrypted?

```zsh
k create secret generic my-secret --from-literal=key1=supersecret

ETCDCTL_API=3 etcdctl \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/my-secret | hexdump -C
```

- `supersecret` readable → **not encrypted**
- Value starts with `k8s:enc:aescbc:v1:key1` → encrypted

Is it enabled on the apiserver?

```zsh
ps aux | grep kube-apiserver | grep encryption-provider-config
grep encryption /etc/kubernetes/manifests/kube-apiserver.yaml
```

### Enable it (kubeadm)

**1. Generate a key**

```zsh
head -c 32 /dev/urandom | base64
```

**2. Write the config** — `/etc/kubernetes/enc/enc.yaml`

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:                 # FIRST provider = used for WRITES
          keys:
            - name: key1
              secret: <BASE64_KEY>
      - identity: {}            # kept so old plain-text data can still be READ
```

Providers: `identity` (none, default), `aescbc`, `aesgcm`, `secretbox`, `kms` (v2, external KMS — the production option).
⚠️ **Order matters**: the first provider encrypts new writes; all providers are tried for reads. `identity` first = no encryption.

**3. Wire it into the static pod** — `/etc/kubernetes/manifests/kube-apiserver.yaml`

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml   # add
    volumeMounts:
    - name: enc                                                   # add
      mountPath: /etc/kubernetes/enc
      readOnly: true
  volumes:
  - name: enc                                                     # add
    hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
```

The kubelet restarts the apiserver automatically (static pod). Wait for it: `watch crictl ps | grep apiserver`.

**4. Re-encrypt the existing Secrets** (only new writes are encrypted)

```zsh
k get secrets -A -o json | k replace -f -
```

Then re-check with `etcdctl ... | hexdump -C`.

### Gotchas

- The key sits in clear text in `enc.yaml` on the control plane → moves the problem, doesn't remove it. Real answer in production: **KMS provider** (envelope encryption, key in AWS KMS / Vault).
- Broken path or typo in the flag → the apiserver won't start → `k` stops responding. Check `crictl ps -a` and `crictl logs <id>`, or `/var/log/pods/`.
- etcd backups taken before enabling still contain plain-text Secrets.
- Context: k3s/k3d → `--secrets-encryption` flag; EKS → envelope encryption with KMS.