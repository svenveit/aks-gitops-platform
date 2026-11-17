# Flux installed as an AKS cluster extension: Azure manages install and upgrades of
# the controllers, and their state is visible in Azure (portal, CLI, Policy).
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"

  # No `version`: Azure installs the latest version and keeps it auto-upgraded
  # (only the latest N-2 versions are supported anyway). Default controllers:
  # source, kustomize, helm, notification; image automation stays off.

  # The Flux pods tolerate CriticalAddonsOnly, so they could all land on the small
  # system node. Installing after the user pool exists lets the scheduler spread
  # them to the less loaded user node instead (verified: 5 of 6 run there).
  depends_on = [
    azurerm_kubernetes_cluster_node_pool.user,
  ]
}

# The Git source and what to apply from it. The extension turns this into a Flux
# GitRepository plus one Flux Kustomization per `kustomizations` block (named
# "<config name>-<kustomization name>"). Flux then pulls from GitHub; nothing pushes
# into the cluster.
resource "azurerm_kubernetes_flux_configuration" "platform" {
  name       = "platform"
  cluster_id = azurerm_kubernetes_cluster.main.id
  namespace  = "flux-system"
  # Cluster scope: the configuration may create namespaces and cluster-wide objects.
  scope = "cluster"

  git_repository {
    # Public repo over HTTPS: no credentials, nothing secret in state.
    url             = var.gitops_repo_url
    reference_type  = "branch"
    reference_value = var.gitops_branch
    # Poll GitHub every minute (default 10 min): fast feedback in a lab.
    sync_interval_in_seconds = 60
  }

  kustomizations {
    name = "infrastructure"
    path = "./infrastructure"
    # Re-apply every minute: manual changes (drift) are reverted within ~1 min.
    sync_interval_in_seconds  = 60
    retry_interval_in_seconds = 60
    # "prune" in Flux terms: objects removed from Git are deleted from the cluster.
    # Defaults to false in azurerm.
    garbage_collection_enabled = true
  }

  kustomizations {
    name = "apps"
    path = "./apps"
    # Namespaces and default-deny policies must exist before the workloads.
    depends_on                 = ["infrastructure"]
    sync_interval_in_seconds   = 60
    retry_interval_in_seconds  = 60
    garbage_collection_enabled = true
  }

  # The configuration only references the cluster, not the extension, so without
  # this Terraform would create both in parallel and the Flux CRDs would be missing.
  depends_on = [
    azurerm_kubernetes_cluster_extension.flux,
  ]
}
