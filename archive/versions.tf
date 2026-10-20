terraform {
  required_version = ">= 1.16.0, < 1.17.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.9.0"
    }
  }
  backend "azurerm" {
    use_cli          = true
    use_azuread_auth = true
  }
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  use_cli                         = true
  storage_use_azuread             = true
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Storage", "Microsoft.ManagedIdentity"]
  features {}
}
