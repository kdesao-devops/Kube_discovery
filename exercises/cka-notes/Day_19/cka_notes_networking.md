# Day 13 — Networking (1/2)

## Linux networking reminders

```bash
cat /proc/sys/net/ipv4/ip_forward              # 0 = no routing between interfaces · 1 = routing enabled
echo 1 > /proc/sys/net/ipv4/ip_forward         # not persistent -> net.ipv4.ip_forward = 1 in /etc/sysctl.conf + sysctl -p
ip link / ip -n <ns> link                      # list interfaces (host / inside a namespace)
ip addr                                        # addresses on each interface
ip addr add 192.168.1.10/24 dev eth0           # without /24 -> /32
ip route                                       # display route table (legacy: route)
ip route add 192.168.2.0/24 via 192.168.1.1    # gateway must be on a directly connected network
ip route add default via 192.168.1.1
ip -n <ns> route                               # = ip netns exec <ns> ip route
ip neigh                                       # ARP table (legacy: arp)
netstat -plnt / ss -plnt                       # process, listening, numeric, tcp (netstat often not installed)
```

| File | Role |
|---|---|
| `/etc/hosts` | Local static name → IP mapping, checked before DNS |
| `/etc/resolv.conf` | Points to a DNS server: `nameserver <dns-ip>` + `search <domain>` |
| `/etc/nsswitch.conf` | Resolution order (`hosts: files dns`) |

---

## Network namespaces

```bash
ip netns add <ns>                              # create a namespace
ip netns                                       # list namespaces
```

### Direct connection (veth pair)

```bash
ip link add <int-name1> type veth peer name <int-name2>   # interfaces + cable between them
ip link set <int-name1> netns <ns1>                       # attach each end to a namespace
ip link set <int-name2> netns <ns2>

ip -n <ns1> addr add <ip1/netmask> dev <int-name1>
ip -n <ns2> addr add <ip2/netmask> dev <int-name2>

ip -n <ns1> link set <int-name1> up
ip -n <ns2> link set <int-name2> up
```

### Switch with a Linux bridge (connect many namespaces)

```bash
ip link add v-net-0 type bridge                           # virtual switch
ip link set v-net-0 up
ip -n <ns1> link del <int-name1>                          # delete the previous cable: deleting one end is enough

ip link add <int-name1> type veth peer name <int-name1-br>   # -br = naming convention for the bridge side
ip link add <int-name2> type veth peer name <int-name2-br>

ip link set <int-name1> netns <ns1>
ip link set <int-name2> netns <ns2>
ip link set <int-name1-br> master v-net-0                 # bridge-side ends go to the switch (no netns keyword)
ip link set <int-name2-br> master v-net-0

ip -n <ns1> addr add <ip1/netmask> dev <int-name1>
ip -n <ns2> addr add <ip2/netmask> dev <int-name2>

ip -n <ns1> link set <int-name1> up
ip -n <ns2> link set <int-name2> up
ip link set <int-name1-br> up                             # don't forget the bridge side
ip link set <int-name2-br> up
```

### Host → namespaces

```bash
ip addr add <host_ip/netmask> dev v-net-0                 # the bridge is an interface of the host
```

### Namespaces → outside of the host

Requires `ip_forward = 1` on the host.

```bash
ip netns exec <ns> ip route add <target-network> via <host_ip>   # through the host (bridge IP)
ip netns exec <ns> ip route add default via <host_ip>            # everything outside
iptables -t nat -A POSTROUTING -s <ns-network> -j MASQUERADE     # NAT for the namespace network
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination <container_ip>:80   # outside -> app port 80
```

> The DNAT rule is what `docker run -p 80:80` creates (in Docker's own `DOCKER` chain). Left number = host port: `-p 8080:80` → `--dport 8080`, to `<ip>:80`.

---

## Docker networking

```bash
docker run --network none <image>     # no network connectivity
docker run --network host <image>     # same network as the host: no isolation, port conflicts
docker run <image>                    # bridge = default mode
```

- **Bridge mode**: for each container Docker creates a network namespace + a veth pair: one end in the container (`eth0`), the other attached to the host bridge `docker0` (network `bridge` in `docker network ls`). Same as the manual bridge lab.

---

## Container Network Interface (CNI)

Every container runtime faced the same network problem → a common standard so that plugins have similar commands and results.

| Part | Role |
|---|---|
| **Container runtime** (containerd, CRI-O) | Creates the network namespace, then calls the CNI plugin with `ADD` (container created) / `DEL` (container deleted) |
| **CNI plugin** (binary) | Creates the veth, attaches it to the bridge, assigns the IP, sets routes, returns JSON |
| **IPAM plugin** (`host-local`, `dhcp`) | Picks a free IP in a range, no duplicates |

- In Kubernetes: **kubelet → (CRI) → containerd → CNI plugin**. The kubelet never configures the network itself.
- **Docker is out**: it uses its own model, **CNM** (libnetwork). K8s worked around it: container started with `--network none`, then CNI plugin called.
- **K8s networking model**: every pod gets its own IP, all pods reach each other across nodes **without NAT**.
- Plugins: Flannel (VXLAN, **no NetworkPolicy**), Calico (BGP/overlay, policies), Cilium (eBPF). Weave = dead, still in old courses.

```bash
ls /opt/cni/bin/                      # plugin binaries (bridge, host-local, loopback, portmap, calico…)
ls /etc/cni/net.d/                    # config: first file in alphabetical order is used
cat /etc/cni/net.d/10-*.conflist      # type = plugin, ipam subnet/ranges = pod IP range
```

> Since 1.24 (dockershim removed), CNI paths are set in the runtime config (`/etc/containerd/config.toml`), not by kubelet flags.

---

## Cluster networking

Everything above is the way the Kubernetes cluster components talk to each other → bear it in mind during debug sessions. **Services** are different: virtual IPs handled by **kube-proxy** (iptables/IPVS) on each node, not by CNI.

| Component | Port |
|---|---|
| kube-apiserver | 6443 |
| kubelet | 10250 |
| kube-scheduler | 10259 |
| kube-controller-manager | 10257 |
| etcd | 2379 (clients) · 2380 (peers) |
| NodePort services | 30000–32767 |

```bash
ss -plnt                              # check what listens on a node
```

---

## To review

- [ ] Redo the namespace + bridge lab from scratch, ping between namespaces and from the host
- [ ] Namespace → outside: route + `ip_forward` + MASQUERADE, then DNAT port 80
- [ ] Find the CNI plugin and the pod IP range on a node (`/etc/cni/net.d`, `/opt/cni/bin`)
- [ ] Know the component ports by heart, verify with `ss -plnt`