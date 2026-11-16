resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # Basic is the cheapest tier (no private endpoints, geo-replication or zone redundancy).
  sku = "Basic"

  # No shared admin username/password; access is via Entra ID + Azure RBAC only
  # (kubelet identity gets AcrPull, you push via `az acr login`).
  admin_enabled = false

  # Legacy mode honours registry-wide roles like AcrPull. The ABAC mode would
  # require repository-scoped roles instead, and AcrPull would no longer apply.
  role_assignment_mode = "LegacyRegistryPermissions"

  tags = local.tags
}
