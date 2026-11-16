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

_TODO (step 2)_

## Deploy

_TODO (step 2)_

## Connect to the cluster

_TODO (step 7)_

## Destroy

_TODO (step 8)_

## Cost notes

_TODO (step 7)_

## Troubleshooting

_TODO (step 7)_
