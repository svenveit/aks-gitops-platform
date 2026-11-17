# aks-gitops-platform

Learning and portfolio repository: an Azure Kubernetes Service (AKS) platform built
with Terraform and managed through GitOps (Flux now, Argo CD later).

- **Phase 1:** Terraform provisions an AKS cluster that mirrors a cluster previously
  built by hand in the Azure portal, with every setting written out as code.
- **Phase 2 (current):** Terraform installs Flux as the AKS cluster extension
  `microsoft.flux`; Flux then reconciles the manifests in this repository.

No registry modules are used, so every resource is visible. One `terraform apply`
brings back the cluster, Flux and all workloads without manual steps.

## Repository structure

```text
.
├── infra/
│   └── terraform/            # Root module
│       ├── versions.tf       # Terraform/provider versions, (commented) remote backend
│       ├── providers.tf      # azurerm provider, Azure CLI auth, provider registration
│       ├── variables.tf      # All inputs (naming, tags, CIDRs, versions, IDs, GitOps repo)
│       ├── main.tf           # Tags, client config, resource group
│       ├── network.tf        # VNet + AKS node subnet
│       ├── acr.tf            # Azure Container Registry
│       ├── aks.tf            # Control plane identity, cluster + system pool, user pool
│       ├── rbac.tf           # Role assignments
│       ├── flux.tf           # Flux extension + Flux configuration
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── infrastructure/           # Flux Kustomization "infrastructure": namespaces, default-deny policies
├── apps/                     # Flux Kustomization "apps" (depends on infrastructure)
│   ├── backend/              #   podinfo: Deployment, Service, PDB, ingress allow rule
│   └── frontend/             #   curl client: Deployment, egress allow rule
└── clusters/                 # Placeholder for later multi-cluster / Argo CD work
```

## Architecture

```text
rg-aks-lab-tf
├── vnet-aks-lab-tf  10.10.0.0/16
│   └── snet-aks-nodes  10.10.0.0/24  ◄── Network Contributor ── id-aks-lab-tf-control-plane
├── id-aks-lab-tf-control-plane         (user-assigned, AKS control plane identity)
├── <acr_name>  (ACR Basic)             ◄── AcrPull ── kubelet identity
└── aks-lab-tf  (AKS Free tier)         ◄── AKS RBAC Cluster Admin ── admin user
    ├── system pool: 1x Standard_D2as_v5   (CriticalAddonsOnly taint)
    ├── user pool:   1x Standard_D2as_v5   (workloads)
    └── extension microsoft.flux  ──pull──►  github.com/<owner>/aks-gitops-platform (main)

rg-aks-lab-tf-nodes  (managed by AKS)
└── VMSS, Standard Load Balancer, outbound public IP, OS disks, kubelet identity
```

| Area | Setting |
|---|---|
| Region | germanywestcentral, no availability zones |
| Kubernetes | `1.37` (minor alias, newest GA patch), auto-upgrade `patch`, node OS `NodeImage` |
| Maintenance | both channels weekly, Sunday 00:00 UTC, 4 h |
| Network | BYO VNet, Azure CNI Overlay, Cilium dataplane + network policy, LB outbound |
| CIDRs | VNet `10.10.0.0/16`, pods `10.244.0.0/16`, services `10.0.0.0/16`, DNS `10.0.0.10` |
| API server | public, no authorized IP ranges |
| Identity | user-assigned control plane identity, AKS-created kubelet identity |
| Auth | Entra ID + Azure RBAC for Kubernetes, local accounts disabled |
| Features | OIDC issuer, workload identity, Image Cleaner (168 h) |
| GitOps | `microsoft.flux` extension (auto-upgrade), public repo over HTTPS, 1 min sync |
| Not enabled (yet) | Container Insights, Managed Prometheus/Grafana, ACNS, Azure Policy, Key Vault CSI, Istio, app routing, Log Analytics |

## Prerequisites

| Tool | Version used |
|---|---|
| Terraform | 1.17.x |
| azurerm provider | 5.14.x |
| Azure CLI | 2.92+, extensions `k8s-extension` and `k8s-configuration` (installed on first use) |
| kubectl / kubelogin | `az aks install-cli` |

Azure permissions: **Owner** on the target subscription (needed for role assignments).
No Entra directory roles are required, so this works as a B2B guest: Entra integration
is AKS-managed (no app registrations), no Entra groups are used, and all role
assignments are Azure RBAC with an explicit `principal_type` (no directory lookups).

Resource providers: Terraform registers `Microsoft.ContainerService` and
`Microsoft.KubernetesConfiguration` if they are missing (provider setting
`resource_providers_to_register`; never unregistered on destroy).
`Microsoft.Network`, `Microsoft.ContainerRegistry`, `Microsoft.ManagedIdentity` and
`Microsoft.Compute` must already be registered (`resource_provider_registrations = "none"`).

## Deploy

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>

cd infra/terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # then edit the values
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

Authentication uses the Azure CLI token. State is local (`terraform.tfstate`, git-ignored);
a commented `backend "azurerm"` block in `versions.tf` is prepared for remote state.

Creation order is enforced with `depends_on` in three places:

1. The control plane identity must hold **Network Contributor** on the subnet before
   the cluster is created.
2. The Flux extension is installed after the user pool exists, so its controllers can
   spread to the user node instead of all landing on the small system node.
3. The Flux configuration is created after the extension (it needs the Flux CRDs).

## Connect to the cluster

```powershell
cd infra/terraform
Invoke-Expression (terraform output -raw get_credentials_command)
kubelogin convert-kubeconfig -l azurecli    # reuse the Azure CLI token, no device code prompt

kubectl get nodes -o wide
```

There is no `--admin` kubeconfig (local accounts are disabled); all access goes
through Entra ID and Azure RBAC.

### Smoke test

```powershell
# 1. Nodes: 2x Ready (system + user), same Kubernetes version
kubectl get nodes -L kubernetes.azure.com/agentpool

# 2. System pods: all Running. Expect cilium, cilium-operator, azure-cns, coredns,
#    konnectivity-agent, metrics-server, azure-wi-webhook, eraser, CSI drivers.
#    There is no kube-proxy: Cilium replaces it.
kubectl get pods -n kube-system -o wide

# 3. Pull from ACR via the kubelet identity (no imagePullSecret).
#    az acr import copies the image server-side, Docker is not needed.
$acr = terraform output -raw acr_login_server
az acr import --name $acr.Split('.')[0] --source docker.io/library/nginx:stable --image nginx:stable
kubectl create deployment nginx --image="$acr/nginx:stable"
kubectl rollout status deployment/nginx
kubectl get pods -l app=nginx -o wide       # lands on the user pool node
kubectl port-forward deployment/nginx 8080:80   # then open http://localhost:8080

# Clean up
kubectl delete deployment nginx
```

## GitOps with Flux

### How it works

Flux uses a **pull model**: nothing outside the cluster needs credentials for it.
Controllers inside the cluster poll GitHub and apply what they find.

1. Terraform creates the extension `microsoft.flux` (Flux controllers plus Microsoft's
   `fluxconfig-agent`/`fluxconfig-controller`) and the Flux configuration `platform`.
2. The extension translates the Flux configuration into native Flux objects in
   `flux-system`: one `GitRepository` (`platform`) and one `Kustomization` per
   `kustomizations` block (`platform-infrastructure`, `platform-apps`).
3. **source-controller** fetches the branch every 60 s and stores the commit as an artifact.
4. **kustomize-controller** runs `kustomize build` on the path, applies the result with
   server-side apply, waits for the objects to become healthy and records them in an
   inventory. This **reconcile loop** repeats every 60 s even without a new commit,
   so manual changes to Flux-managed objects are reverted (drift correction).
5. With prune (`garbage_collection_enabled = true`), objects that disappear from Git
   are deleted from the cluster, based on that inventory.
6. `fluxconfig-agent` reports the state back to Azure as the configuration's
   **compliance state**.

| Flux configuration setting | Value | Why |
|---|---|---|
| Source | `https://github.com/<owner>/aks-gitops-platform`, branch `main` | public repo, no credentials in state |
| Scope / namespace | `cluster` / `flux-system` | may create namespaces and cluster-wide objects |
| Source and reconcile interval | 60 s (retry 60 s) | fast feedback in a lab (default 10 min) |
| Prune | enabled on both Kustomizations | Git is the only source of truth |
| `apps` depends on `infrastructure` | yes | namespaces and default-deny policies first |

The extension runs with multi-tenancy enabled (its default): the Kustomizations apply
as the service account `flux-applier`. This only restricts cross-namespace references
between Flux objects, which this repo does not use.

Only changes **pushed to GitHub** take effect; local commits are invisible to Flux.
The Flux objects carry the label `clusterconfig.azure.com/is-managed=true`: change
them through Terraform, not with `kubectl` (the agent would revert it).

### What gets deployed

| Path | Objects |
|---|---|
| `infrastructure/` | namespaces `frontend` and `backend` (label `purpose: demo`); `default-deny-ingress` in `backend`; `default-deny-egress` in `frontend` |
| `apps/backend/` | `podinfo` (ghcr.io/stefanprodan/podinfo:6.17.0): Deployment, ClusterIP Service on 9898, PDB `maxUnavailable: 1`; NetworkPolicy allowing ingress only from `app: client` in `frontend` on TCP 9898 |
| `apps/frontend/` | `client` (curlimages/curl:8.23.0, `sleep infinity`); NetworkPolicy allowing egress only to podinfo on TCP 9898 and CoreDNS on UDP/TCP 53 |

Images are public because the ACR is destroyed together with the environment.

### Check status

```powershell
# Flux objects: all READY=True, same revision as `git rev-parse origin/main`
kubectl get gitrepositories,kustomizations -n flux-system

# Details and the last error of one Kustomization
kubectl describe kustomization platform-apps -n flux-system
kubectl get events -n flux-system --sort-by=.lastTimestamp
kubectl logs -n flux-system deploy/kustomize-controller --tail=50

# Result in the cluster
kubectl get ns -l purpose=demo
kubectl get networkpolicy -A
kubectl get deploy,svc,pdb,pods -n backend -o wide
kubectl get deploy,pods -n frontend -o wide

# Compliance state as seen by Azure (Compliant / Succeeded)
cd infra/terraform
Invoke-Expression (terraform output -raw flux_compliance_command)
```

Force an immediate reconcile instead of waiting up to a minute (no Flux CLI needed):

```powershell
$now = Get-Date -Format o
kubectl annotate gitrepository platform -n flux-system reconcile.fluxcd.io/requestedAt=$now --overwrite
kubectl annotate kustomization platform-apps -n flux-system reconcile.fluxcd.io/requestedAt=$now --overwrite
```

### Test network policies

```powershell
# Allowed: client -> podinfo (returns podinfo's JSON with the pod hostname)
kubectl exec -n frontend deploy/client -- curl -sS --max-time 5 http://podinfo.backend:9898

# Blocked: client -> internet. DNS still resolves (port 53 is allowed),
# the TCP connection times out (curl exit code 28).
kubectl exec -n frontend deploy/client -- curl -sS --max-time 5 https://example.com

# Blocked: a pod without app=client in frontend gets no egress at all, not even DNS
kubectl run tmp -n frontend --image=curlimages/curl:8.23.0 --rm -it --restart=Never -- `
  curl -sS --max-time 5 http://podinfo.backend:9898
```

### Test GitOps behaviour

**Drift correction**: change the cluster by hand, Flux reverts it within ~1 minute.

```powershell
kubectl delete deployment podinfo -n backend
kubectl get deployment podinfo -n backend -w      # re-created by the next reconcile

kubectl scale deployment podinfo -n backend --replicas=1
kubectl get deployment podinfo -n backend -w      # back to the replica count in Git
```

**Change via Git**: edit `replicas` in `apps/backend/podinfo-deployment.yaml`, commit
and push. Within ~1-2 minutes the GitRepository shows the new revision and the
Deployment is scaled.

**Prune**: delete `apps/backend/podinfo-pdb.yaml` **and** its entry in
`apps/backend/kustomization.yaml`, commit and push. Flux deletes the PDB from the
cluster. (Deleting only the file breaks `kustomize build`; see troubleshooting.)
Restore it with `git revert`.

### Timings

Measured on 2026-11-17 from the Flux objects' timestamps:

| Phase | Duration |
|---|---|
| Flux configuration created → `platform-infrastructure` applied | ~2 s |
| Flux configuration created → `platform-apps` applied (after infrastructure, incl. health checks) | ~40 s |

## Destroy

```powershell
cd infra/terraform
terraform destroy
```

This removes both resource groups (AKS deletes `rg-aks-lab-tf-nodes` together with
the cluster). Afterwards, `az group list --query "[?starts_with(name,'rg-aks-lab-tf')]" -o table`
should return nothing. The resource provider registrations stay in place.

Measured on 2026-11-16 (Phase 1, germanywestcentral, local state):

| Operation | Duration |
|---|---|
| `terraform destroy` | 5:20 min |
| `terraform apply` (full rebuild from empty subscription) | 10:02 min |

Most of the apply time is the cluster with its system pool, followed by the user pool;
network, identity, ACR and role assignments take well under a minute.

## Cost notes

This is a lab sized for minimum cost; destroy it when not in use.

| Resource | Billed while |
|---|---|
| 2x Standard_D2as_v5 (system + user VMSS) | nodes are running |
| 2x 64 GB managed OS disks | the cluster exists (also when stopped) |
| Standard Load Balancer + 1 outbound public IP | the cluster exists |
| ACR Basic | the registry exists (fixed daily rate) |
| AKS control plane, Flux extension | free (Free tier, no SLA) |

The user pool originally used the cheaper burstable `Standard_B2as_v2`, but creating
it failed with `AllocationFailed` in germanywestcentral, so both pools now use
`Standard_D2as_v5`.

The VMs are the main cost driver. Options, cheapest first:

1. `terraform destroy`: nothing is billed. A full rebuild takes about 10 minutes (see above).
2. `az aks stop -g rg-aks-lab-tf -n aks-lab-tf`: stops all nodes; disks, public IP
   and ACR are still billed. `az aks start` resumes it.
3. Scale the user pool to 0 (`node_count = 0`) and keep only the system node.

Check current prices with the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
for germanywestcentral.

## Troubleshooting

### Azure / Terraform

**`AADSTS50076` / MFA claims challenge during `terraform apply`**
Conditional Access requires MFA for write operations, and the cached CLI token
lacks the MFA claim. Re-authenticate and re-run:

```powershell
az logout
az login --tenant <tenant-id> --scope https://management.core.windows.net//.default
# or use the exact `az login --claims-challenge "..."` command printed in the error
```

**`kubectl` returns `Forbidden` right after the first apply**
Azure RBAC role assignments take a few minutes (sometimes up to ~10) to propagate.
Wait and retry; no re-apply is needed. Check the assignment with
`az role assignment list --scope (az aks show -g rg-aks-lab-tf -n aks-lab-tf --query id -o tsv) -o table`.
Note that Owner on the subscription does **not** grant Kubernetes API access:
it has no `dataActions`.

**`kubectl` asks for a device code login, or cannot resolve the API server**
Run `kubelogin convert-kubeconfig -l azurecli` after `az aks get-credentials`. After a
rebuild the API server has a new FQDN, so fetch credentials again.

**Node pool creation fails with `AllocationFailed`**
The region has no capacity for that VM size at the moment. Retry later or choose
another size (see cost notes).

**Pods fail with `ImagePullBackOff` from the ACR**
Verify AcrPull with `az aks check-acr -g rg-aks-lab-tf -n aks-lab-tf --acr <acr>.azurecr.io`.
The ACR uses `LegacyRegistryPermissions`; in ABAC mode AcrPull would not apply.

**Cluster creation fails with a permission error on the subnet**
The Network Contributor assignment was not yet effective. Wait a few minutes and
re-run `terraform apply`.

**ACR name not available**
ACR names are globally unique; change `acr_name` in `terraform.tfvars`.

**Flux configuration fails because `Microsoft.KubernetesConfiguration` is not registered**
Terraform registers it on the next plan/apply (`resource_providers_to_register`);
registration can take a few minutes. Check with
`az provider show -n Microsoft.KubernetesConfiguration --query registrationState`.

### Flux

**A change in Git is not applied**
Check that it is pushed: the GitRepository's revision must match `git rev-parse origin/main`.
Then force a reconcile (see "Check status").

**`platform-apps` shows `dependency ... platform-infrastructure is not ready`**
Expected for a short time after creation; `apps` waits for `infrastructure`.
If it persists, fix `platform-infrastructure` first.

**Kustomization `Ready=False` with `kustomize build failed` / `no such file or directory`**
A file was deleted but is still listed in a `kustomization.yaml` (or the reverse).
Validate locally before pushing: `kubectl kustomize infrastructure` and `kubectl kustomize apps`.
While the build fails, Flux keeps the last successfully applied revision in place.

**Kustomization `Ready=False` with a health check timeout**
`wait` is enabled, so Flux waits for Deployments to become available. Look at the
pods (`ImagePullBackOff`, failing probes, `Pending`) in the target namespace.

**Azure shows `Non-Compliant` or `Pending` while the cluster looks fine**
The compliance state is reported by `fluxconfig-agent` and can lag a minute behind.
Check `kubectl logs -n flux-system deploy/fluxconfig-agent --tail=50`.

**`curl` from the client to podinfo times out**
Check both allow rules (`kubectl get networkpolicy -A`) and the labels: the client pod
needs `app: client`, podinfo `app: podinfo`. The default-deny policies block anything
that is not explicitly allowed, including DNS.
