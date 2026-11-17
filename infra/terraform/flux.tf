# Flux installed as an AKS cluster extension: Azure manages install and upgrades of
# the controllers, and their state is visible in Azure (portal, CLI, Policy).
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"

  # No `version`: Azure installs the latest version and keeps it auto-upgraded
  # (only the latest N-2 versions are supported anyway). Default controllers:
  # source, kustomize, helm, notification; image automation stays off.

  # The Flux pods do not tolerate the CriticalAddonsOnly taint of the system pool,
  # so they need the user pool. Without this, Terraform creates the extension in
  # parallel with the user pool and the install can hang with Pending pods.
  depends_on = [
    azurerm_kubernetes_cluster_node_pool.user,
  ]
}
