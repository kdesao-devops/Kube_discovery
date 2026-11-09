# Day 10 — Security

## Security for different users

| Who | How they're managed |
|---|---|
| Cluster admins | Users are not managed by kube |
| Developers | Users are not managed by kube |
| Application users | Are managed by the application, not the cluster |
| In/outside integration bots | Service accounts are managed in kube |

- Basically every component of kube has its own cert + key pair (admin/dev user included).
- Groups are mentioned in the certificate (O field), e.g. `system:masters` for the admin.
  - On recent kubeadm (1.29+), `admin.conf` uses `kubeadm:cluster-admins` (bound via RBAC); `system:masters` (bypasses RBAC) is kept for the break-glass `super-admin.conf`.
- kube-apiserver has a server cert and a client cert (apiserver as server, and as client for etcd + kubelet + extension API, e.g. metrics).
- Node (= kubelet) also has a server and client cert: client of the apiserver, and server for the apiserver (`logs` / `exec` / `port-forward` on port 10250).
- The cluster has its own `ca.crt` / `ca.key`.

### Auth mechanism

- **Static token file** (`--token-auth-file`): a CSV file (token, user, uid, groups) passed on cluster creation to the apiserver and used to authenticate users and attribute groups.

---

## LAB — Viewing certs

```bash
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -i cert
- --tls-cert-file=/etc/kubernetes/pki/apiserver.crt                  # kube-apiserver server cert
- --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt      # kube-apiserver client cert for etcd

cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -i key
- --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key   # kube-apiserver cert client key for kubelet

cat /etc/kubernetes/manifests/etcd.yaml | grep cert -i
- --cert-file=/etc/kubernetes/pki/etcd/server.crt                    # etcd server certificate

cat /etc/kubernetes/manifests/etcd.yaml | grep ca -i
- --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt                  # etcd ca cert

openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout | grep -i cn
        Issuer: CN = kubernetes
        Subject: CN = kube-apiserver

crictl ps -a | grep kube-apiserver     # to get the container id — very important the -a, else the killed containers won't appear
crictl logs 7745551679a02              # check the logs
```

> `127.0.0.1:2379` → etcd port!

- [ ] Prévoir un exercice de debug de cert, les labs étaient durs (je me sens dépourvu face à mon terminal :( )

---

## LAB — Certificate API

The authentication being managed through certificates signed by the cluster, an API command exists to ease the process. Indeed a `CertificateSigningRequest` API object is created, an admin approves it (`k certificate approve`), then the controller manager signs the approved CSR and puts the cert in `status.certificate`.

Doc: https://kubernetes.io/docs/tasks/tls/certificate-issue-client-csr/

```bash
openssl req -in akshay.csr -text -noout
cat akshay.csr | base64 | tr -d "\n"
k get certificatesigningrequest.certificates.k8s.io/akshay
k certificate approve akshay
k auth can-i get pods --as akshay     # In the CSR she doesn't mention any group, she is authenticated (CN=akshay) but has no permission, this command returns « no »
k get csr akshay -o jsonpath='{.status.certificate}' | base64 -d > akshay.crt
openssl x509 -in akshay.crt -text -noout
```

### Using the user

```bash
kubectl config set-credentials myuser --client-key=akshay.key --client-certificate=akshay.crt --embed-certs=true   # declare the credentials
kubectl config set-context myuser --cluster=kubernetes --user=myuser                                                # create a context cluster + user with credentials already set
kubectl --context myuser auth whoami                                                                                # use the context to pass command auth whoami
kubectl --context myuser get pods                                                                                   # get 403 as the user has no right
# Error from server (Forbidden): pods is forbidden: User "akshay" cannot list resource "pods" in API group "" in the namespace "default"
kubectl --client-certificate=akshay.crt --client-key=akshay.key get pods                                            # all the previous in one line
```

### Deny / delete a CSR

```bash
k get -o yaml certificatesigningrequest.certificates.k8s.io/agent-smith
k describe certificatesigningrequest.certificates.k8s.io/agent-smith
k certificate deny agent-smith
k delete certificatesigningrequests.certificates.k8s.io agent-smith
```

---

## Config files

Kubernetes credentials / cluster address can be configured for easy kubectl commands in a config file.

- Goes into it: clusters address and cert + key file path.
- It can be used by selecting the right combination on every command,
- or can be set as context (`--context admin@google`).
- Also the namespace can be set directly in a predefined context.

### LAB — config file

```yaml
apiVersion: v1
current-context: kubernetes-admin@kubernetes
kind: Config
clusters:
- cluster:
    certificate-authority-data: <OINOZE>   # base64 encoded cert
    server: https://controlplane:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
    namespace: dev
  name: kubernetes-admin@kubernetes
users:
- name: kubernetes-admin
  user:
    client-certificate: /home/keuvin/kebab.crt   # full path or relative path, relative being to the kubeconfig file's directory (~/.kube/)
    client-key: kebab.key                        # Here an example of the file kebab.key being in ~/.kube/
```