Here is your drill converted into **mission prompts**. No commands, no copy-pasting—just operational objectives that force muscle memory and command recall.

---

### Phase 0: Exam Environment Muscle Memory

1. Enable tab-completion for `kubectl` in your current Zsh shell so you never type full resource names manually.
2. Create an alias so single-letter `k` invokes `kubectl`, and ensure shell auto-completion works seamlessly with this alias.
3. Export an environment variable named `do` configured to perform a client-side dry run and output clean YAML format.
4. Export an environment variable named `now` to force-kill resources immediately without waiting for a grace period.

---

### Phase 1: Local Cluster Provisioning

5. Using `k3d`, spin up a new cluster named `lab` consisting of exactly 1 control-plane node (server) and 2 worker nodes (agents), while mapping local host ports `80` and `443` directly to the cluster load balancer.

`k3d cluster create drill --servers 1 --agents 2 -p "80:80@loadbalancer" -p "443:443@loadbalancer"`

---

### Phase 2: Context & Scoping

6. Create an isolated workspace/namespace named `demo`.
`k create ns drill`
7. Permanently update your active context so that all subsequent commands run inside `demo` by default without having to append `-n demo`.
`k config set-context --current --namespace=drill`

---

### Phase 3: Workload Deployment & Basic Networking

8. Imperatively launch a deployment named `web` using the `ghcr.io/stefanprodan/podinfo:6.7.1` image, running with an initial scale of 2 replicas.
`k create deployment drillweb --image=ghcr.io/stefanprodan/podinfo:6.7.1 --replicas=2`
9. Expose this deployment as an internal service named `web` that listens on port `80` and routes incoming traffic to container port `9898`.
`k expose deployment.apps/drillweb --port=80 --target-port=9898`
10. Establish a temporary port-forward from your laptop's local port `9898` directly to port `80` of the `web` service to verify connectivity in your browser.
`k port-forward services/drillweb 9898:80`
11. Query your cluster in a single invocation to inspect all deployments, replica sets, running pods, and services within your active namespace.
`k get deployments,rc,pods,svc`
12. Inspect the running pods with extended details to identify which worker node hosts each individual pod and view their assigned cluster IPs.
`k get pods -o wide`

---

### Phase 4: Self-Healing, Scaling & Rollout Lifecycles

13. Force-terminate all pods matching the selector label `app=web` simultaneously, and observe which controller intervenes to maintain desired state.
`k delete pod -l app=drillweb`
14. Imperatively scale the `web` deployment up from 2 replicas to 4 replicas.
`k scale --replicas 4 deployment/drillweb`
15. Perform an in-place rolling update on container `podinfo` within deployment `web` by swapping its image tag to version `6.7.0`.
`k set image deployments drillweb podinfo=ghcr.io/stefanprodan/podinfo:6.7.0`
16. Monitor the rollout progression until all updated replicas are successfully updated and available.
`k rollout status deployment drillweb`
17. Review the revision history of deployment `web` to track past rollouts and revisions.
`k rollout history deployment drillweb`
18. Format a custom output using `custom-columns` that extracts and displays only two fields for every pod: the pod's name and its container specification image.
`k get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers`
19. Trigger a rollback on the `web` deployment to revert it to its immediately preceding revision (`6.7.1`).
`k rollout undo deployment drillweb`
20. Inspect both deployments and replica sets with wide output to verify image tags, selector labels, and active pod counts across revisions.
`k get pods,deploy -o wide`

---

### Phase 5: Debugging & In-Cluster Exploration ("Read, Don't Guess")

21. Select any individual pod in the namespace and inspect its detailed runtime definition, scrolling down specifically to analyze its life-cycle lifecycle Events.
`k describe pod/drillweb-7478b64546-fg2dm`
22. Stream/fetch the stdout logs produced by all pods belonging to the `web` deployment.
`k logs deployments/drillweb`
23. Look up the official schema definition and field explanations for `spec.strategy` under `Deployment` directly from your terminal rather than checking online documentation.
`k explain deployment.spec.strategy`

---

### Phase 6: Ingress Routing & Service Discovery

24. Generate the declarative YAML configuration for an ingress named `web` matching host `web.localtest.me` (path `/*`) routed to service `web` on port `80`, using your dry-run shortcut to pipe the output into `ingress.yaml` without creating it immediately.
`k create ingress drillweb --rule="web.localtest.me/*=drillweb:80" $do > exercises/cka-notes/Day_6/ingress.yaml`
25. Inspect the generated `ingress.yaml` file to ensure the structure, paths, and service references conform to Kubernetes specifications.
`cat exercises/cka-notes/Day_6/ingress.yaml`
26. Apply the manifest file to instantiate the ingress resource.
`k apply -f exercises/cka-notes/Day_6/ingress.yaml`
27. Validate external traffic routing by querying `[http://web.localtest.me](http://web.localtest.me)` via `curl` and piping the structured response through `jq`.
`curl http://web.localtest.me | jq`
28. Inspect the status, hosts, and address of the newly created Ingress.
`k get ingress`
29. Inspect the underlying Endpoint/EndpointSlice objects tied to service `web` to verify that active pod IPs are registered targets.
`k get endpoints drillweb`
---

### Phase 7: Cluster Inspection & Tear Down

30. Launch an interactive terminal UI (`k9s`) to navigate your resources, inspect logs, and observe events visually.
`k9s`
31. Once done drilling, completely tear down and destroy the `lab` cluster to release local Docker resources.
`k3d cluster delete drill`