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

# Lets nodes pull images from our ACR without imagePullSecrets. The kubelet
# identity (created by AKS in the node RG) is what the kubelet uses to pull.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id

  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# With Azure RBAC for Kubernetes, Owner on the subscription grants no access to
# the Kubernetes API (no dataActions). This role gives full cluster-admin rights
# via Entra ID, scoped to this cluster only.
resource "azurerm_role_assignment" "admin_user_cluster_admin" {
  scope                = azurerm_kubernetes_cluster.main.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.admin_user_object_id
  principal_type       = "User"
}
