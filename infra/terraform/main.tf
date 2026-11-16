# Tenant/subscription of the current Azure CLI login (read from the token, no Graph call).
data "azurerm_client_config" "current" {}

locals {
  # Applied to every resource that supports tags (the node pools pass them to the VMSS).
  tags = {
    owner          = var.owner
    purpose        = "lab"
    "delete-after" = var.delete_after
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
