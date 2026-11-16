# Bring-your-own VNet: we own the address plan and can later add subnets
# (e.g. private endpoints, App Gateway) next to the cluster without rebuilding it.
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.cluster_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.vnet_address_space]
  tags                = local.tags
}

# Node subnet only. With CNI Overlay, pod IPs come from pod_cidr, so a /24
# (~250 nodes) is plenty and no pod subnet is needed.
resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_prefix]
}
