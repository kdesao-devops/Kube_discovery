# Day 7 — ConfigMaps, Secrets & environment variables

## Ways to pass environment variables to a container

1. **Directly in the container definition** — `env` field, a list of objects (`name` + `value`)
   `k explain pod.spec.containers.env` → `FIELD: env <[]EnvVar>`
2. **Single key from a ConfigMap** — `pod.spec.containers.env.valueFrom.configMapKeyRef` (ConfigMap name + key)
   ⚠️ The ConfigMap must exist **before** the Pod is created, otherwise → `CreateContainerConfigError`
3. **Entire ConfigMap** — `pod.spec.containers.envFrom.configMapRef`: every key becomes a variable
4. **ConfigMap as files in a volume** — one file per key, file name = key, file content = value
5. **Secrets** — same patterns: `secretKeyRef` (single key), `secretRef` (whole Secret), or volume

| Need | Field |
|---|---|
| One literal value | `env[].value` |
| One key from a ConfigMap | `env[].valueFrom.configMapKeyRef` |
| All keys of a ConfigMap | `envFrom[].configMapRef` |
| One key from a Secret | `env[].valueFrom.secretKeyRef` |
| All keys of a Secret | `envFrom[].secretRef` |
| Keys as files | `volumes[].configMap` / `volumes[].secret` + `volumeMounts` |

---

## ConfigMaps

```zsh
k get cm
k describe cm db-config
```

Generate the YAML only (dry-run):

```zsh
k create configmap webapp-config-map --dry-run=client -o yaml \
  --from-literal=APP_COLOR=darkblue \
  --from-literal=APP_OTHER=disregard
```

Generate, save and apply in one go:

```zsh
k create configmap webapp-config-map --dry-run=client -o yaml \
  --from-literal=APP_COLOR=darkblue \
  --from-literal=APP_OTHER=disregard > webapp-config-map.yaml && k apply -f webapp-config-map.yaml
```

### Single key → env variable

```yaml
spec:
  containers:
  - name: webapp
    image: nginx
    env:
    - name: APP_COLOR
      valueFrom:
        configMapKeyRef:
          name: webapp-config-map
          key: APP_COLOR
```

### Entire ConfigMap → env variables

```yaml
spec:
  containers:
  - name: webapp
    image: nginx
    envFrom:
    - configMapRef:
        name: webapp-config-map   # every key becomes a variable
      prefix: CFG_                # optional: APP_COLOR -> CFG_APP_COLOR
```

### ConfigMap as files (volume)

```yaml
spec:
  containers:
  - name: webapp
    image: nginx
    volumeMounts:
    - name: config
      mountPath: /etc/config      # -> /etc/config/APP_COLOR, /etc/config/APP_OTHER
  volumes:
  - name: config
    configMap:
      name: webapp-config-map
```

---

## Secrets

```zsh
k get secrets
k describe secret db-secret                                   # shows keys, not values
k get secret db-secret -o jsonpath='{.data.DB_Password}' | base64 -d   # decode a value
```

Generate, save and apply:

```zsh
k create secret generic db-secret --dry-run=client -o yaml \
  --from-literal=DB_Host=sql01 \
  --from-literal=DB_User=root \
  --from-literal=DB_Password=password123 > webapp-secret-map.yaml && k apply -f webapp-secret-map.yaml
```

### Entire Secret → env variables

```yaml
spec:
  containers:
  - name: webapp
    image: nginx
    envFrom:
    - secretRef:
        name: db-secret
```

### Single key from a Secret

```yaml
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: DB_Password
```

---

## Gotchas to remember

- `env` and `envFrom` can be combined; on duplicate names, **`env` wins**.
- Env vars are set **at container start** → changing the ConfigMap/Secret requires a restart (`k rollout restart deploy/<name>`). Volume-mounted ConfigMaps update automatically (except with `subPath`).
- `envFrom` silently skips keys that aren't valid env var names (e.g. `app.properties`).
- Secrets are only **base64-encoded**, not encrypted.
- `$(VAR)` in `value` expands variables defined **earlier** in the `env` list.
- Imperative shortcut on a Deployment: `k set env deploy/web --from=configmap/webapp-config-map`
- Pod `env` cannot be edited on a running Pod → `k edit` fails, then `k replace --force -f /tmp/kubectl-edit-xxx.yaml`.