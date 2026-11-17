output "resource_group_name" {
  description = "Resource group of the cluster, network, identity and ACR."
  value       = azurerm_resource_group.main.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.main.name
}

output "node_resource_group" {
  description = "AKS-managed resource group with VMSS, load balancer, public IP and disks."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "acr_login_server" {
  description = "Login server of the container registry (image prefix)."
  value       = azurerm_container_registry.main.login_server
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL; needed later for workload identity federated credentials."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "get_credentials_command" {
  description = "Writes the Entra ID kubeconfig for this cluster (no --admin: local accounts are disabled)."
  # --subscription makes the command work regardless of the current `az account` context.
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --subscription ${data.azurerm_client_config.current.subscription_id} --overwrite-existing"
}

output "flux_configuration_name" {
  description = "Name of the Flux configuration (Flux objects are prefixed with it)."
  value       = azurerm_kubernetes_flux_configuration.platform.name
}

output "flux_compliance_command" {
  description = "Shows the Flux configuration's compliance state as seen by Azure (needs the k8s-configuration CLI extension)."
  value       = "az k8s-configuration flux show --resource-group ${azurerm_resource_group.main.name} --cluster-name ${azurerm_kubernetes_cluster.main.name} --cluster-type managedClusters --name ${azurerm_kubernetes_flux_configuration.platform.name} --query \"{compliance:complianceState, provisioning:provisioningState}\" -o table"
}
