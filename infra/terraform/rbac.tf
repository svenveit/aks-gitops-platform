# The AKS control plane joins node NICs and the load balancer to our subnet, which
# lives outside the node RG. Without this role, cluster creation (and later LB/
# node operations) fails. Scoped to the subnet only (least privilege).
# The cluster resource must depend on this assignment so it exists before AKS starts.
resource "azurerm_role_assignment" "aks_control_plane_network_contributor" {
  scope                = azurerm_subnet.aks_nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id

  # Setting the type avoids a directory lookup of the principal (no Entra read
  # rights needed as guest) and tolerates replication lag of the new identity.
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
