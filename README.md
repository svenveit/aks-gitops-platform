# aks-gitops-platform

Learning and portfolio repository: an Azure Kubernetes Service (AKS) platform built
with Terraform and, in later phases, managed through GitOps (Flux, then Argo CD).

**Phase 1 (current):** Terraform provisions an AKS cluster that mirrors a cluster
previously built by hand in the Azure portal, with every setting written out as code.

## Repository structure

```text
.
├── infra/
│   └── terraform/      # Root module: resource group, network, identity, ACR, AKS, RBAC
├── clusters/           # (Phase 2) Flux entry points per cluster
├── infrastructure/     # (Phase 2) Shared cluster components (controllers, CRDs, ...)
└── apps/               # (Phase 2) Application workloads
```

## Architecture

_TODO (step 7)_

## Prerequisites

| Tool | Version used |
|---|---|
| Terraform | 1.17.x |
| Azure CLI | 2.92+ |
| kubectl / kubelogin | `az aks install-cli` |

Azure permissions: **Owner** on the target subscription (needed for role assignments).
No Entra directory roles are required: Entra integration is AKS-managed (no app
registrations), and all role assignments are Azure RBAC.

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

## Connect to the cluster

_TODO (step 7)_

## Destroy

_TODO (step 8)_

## Cost notes

_TODO (step 7)_

## Troubleshooting

_TODO (step 7)_
