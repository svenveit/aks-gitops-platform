# aks-gitops-platform

Learning and portfolio repository: an Azure Kubernetes Service (AKS) platform built
with Terraform and, in later phases, managed through GitOps (Flux, then Argo CD).

**Phase 1 (current):** Terraform provisions an AKS cluster that mirrors a cluster
previously built by hand in the Azure portal, with every setting written out as code.
No registry modules are used, so every resource is visible.

## Repository structure

```text
.
├── infra/
│   └── terraform/            # Root module
│       ├── versions.tf       # Terraform/provider versions, (commented) remote backend
│       ├── providers.tf      # azurerm provider, Azure CLI auth
│       ├── variables.tf      # All inputs (naming, tags, CIDRs, versions, IDs)
│       ├── main.tf           # Tags, client config, resource group
│       ├── network.tf        # VNet + AKS node subnet
│       ├── acr.tf            # Azure Container Registry
│       ├── aks.tf            # Control plane identity, cluster + system pool, user pool
│       ├── rbac.tf           # Role assignments
│       ├── outputs.tf
│       └── terraform.tfvars.example
├── clusters/                 # (Phase 2) Flux entry points per cluster
├── infrastructure/           # (Phase 2) Shared cluster components (controllers, CRDs, ...)
└── apps/                     # (Phase 2) Application workloads
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
    └── user pool:   1x Standard_B2as_v2   (workloads)

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
| Not enabled (yet) | Container Insights, Managed Prometheus/Grafana, ACNS, Azure Policy, Key Vault CSI, Istio, app routing, Log Analytics |

## Prerequisites

| Tool | Version used |
|---|---|
| Terraform | 1.17.x |
| azurerm provider | 5.14.x |
| Azure CLI | 2.92+ |
| kubectl / kubelogin | `az aks install-cli` |

Azure permissions: **Owner** on the target subscription (needed for role assignments).
No Entra directory roles are required, so this works as a B2B guest: Entra integration
is AKS-managed (no app registrations), no Entra groups are used, and all role
assignments are Azure RBAC with an explicit `principal_type` (no directory lookups).

Resource providers `Microsoft.ContainerService`, `Microsoft.Network`,
`Microsoft.ContainerRegistry`, `Microsoft.ManagedIdentity` and `Microsoft.Compute`
must already be registered. The provider is configured with
`resource_provider_registrations = "none"` and will not register them.

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

Creation order matters in one place: the control plane identity must hold
**Network Contributor** on the subnet before the cluster is created, which
`depends_on` in `aks.tf` enforces.

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

## Destroy

```powershell
cd infra/terraform
terraform destroy
```

This removes both resource groups (AKS deletes `rg-aks-lab-tf-nodes` together with
the cluster). Afterwards, `az group list --query "[?starts_with(name,'rg-aks-lab-tf')]" -o table`
should return nothing.

| Operation | Duration |
|---|---|
| `terraform destroy` | _TODO (step 8)_ |
| `terraform apply` (full rebuild) | _TODO (step 8)_ |

## Cost notes

This is a lab sized for minimum cost; destroy it when not in use.

| Resource | Billed while |
|---|---|
| 1x Standard_D2as_v5 + 1x Standard_B2as_v2 (VMSS) | nodes are running |
| 2x 64 GB managed OS disks | the cluster exists (also when stopped) |
| Standard Load Balancer + 1 outbound public IP | the cluster exists |
| ACR Basic | the registry exists (fixed daily rate) |
| AKS control plane | free (Free tier, no SLA) |

The VMs are the main cost driver. Options, cheapest first:

1. `terraform destroy`: nothing is billed. A rebuild takes only minutes (see above).
2. `az aks stop -g rg-aks-lab-tf -n aks-lab-tf`: stops all nodes; disks, public IP
   and ACR are still billed. `az aks start` resumes it.
3. Scale the user pool to 0 (`node_count = 0`) and keep only the system node.

Check current prices with the [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/)
for germanywestcentral.

## Troubleshooting

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

**`kubectl` asks for a device code login**
Run `kubelogin convert-kubeconfig -l azurecli` after `az aks get-credentials`.

**Pods fail with `ImagePullBackOff` from the ACR**
Verify AcrPull with `az aks check-acr -g rg-aks-lab-tf -n aks-lab-tf --acr <acr>.azurecr.io`.
The ACR uses `LegacyRegistryPermissions`; in ABAC mode AcrPull would not apply.

**Cluster creation fails with a permission error on the subnet**
The Network Contributor assignment was not yet effective. Wait a few minutes and
re-run `terraform apply`.

**ACR name not available**
ACR names are globally unique; change `acr_name` in `terraform.tfvars`.
