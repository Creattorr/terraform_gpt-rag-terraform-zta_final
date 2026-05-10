provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
  storage_use_azuread             = true
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
