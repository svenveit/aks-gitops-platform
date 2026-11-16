# Control plane identity (user-assigned instead of system-assigned).
# Its principal exists before the cluster, so we can grant it rights on the subnet
# up front; it also survives a cluster rebuild, keeping its role assignments.
resource "azurerm_user_assigned_identity" "aks_control_plane" {
  name                = "id-${var.cluster_name}-control-plane"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.tags
}
