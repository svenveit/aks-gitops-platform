provider "azurerm" {
  features {}

  # null = fall back to ARM_SUBSCRIPTION_ID or the current `az account show` subscription.
  subscription_id = var.subscription_id

  # Authenticate with the Azure CLI token (`az login`); no service principal or secret needed.
  use_cli = true

  # Don't register the large predefined sets (also the 5.x default; set explicitly).
  resource_provider_registrations = "none"

  # Register only what this config needs and may be missing in a fresh subscription.
  # Unlike azurerm_resource_provider_registration, this is not a resource, so
  # `terraform destroy` never unregisters it (other workloads may depend on it).
  resource_providers_to_register = [
    "Microsoft.ContainerService",
    "Microsoft.KubernetesConfiguration", # cluster extensions + Flux configurations
  ]
}
