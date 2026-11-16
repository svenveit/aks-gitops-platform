provider "azurerm" {
  features {}

  # null = fall back to ARM_SUBSCRIPTION_ID or the current `az account show` subscription.
  subscription_id = var.subscription_id

  # Authenticate with the Azure CLI token (`az login`); no service principal or secret needed.
  use_cli = true

  # Resource providers are already registered in the subscription. "none" skips the
  # registration calls on init (also the 5.x default; set explicitly for clarity).
  resource_provider_registrations = "none"
}
