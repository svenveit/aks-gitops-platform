terraform {
  required_version = ">= 1.17.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # ~> 5.14 allows 5.14.x and later 5.x minors, never 6.0 (breaking changes).
      version = "~> 5.14"
    }
  }

  # Local state for now. To move state to Azure Storage later, create the
  # storage account/container, uncomment this block and run `terraform init -migrate-state`.
  # use_azuread_auth uses your Entra identity instead of storage account keys.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "<globally-unique-name>"
  #   container_name       = "tfstate"
  #   key                  = "aks-gitops-platform.tfstate"
  #   use_azuread_auth     = true
  # }
}
