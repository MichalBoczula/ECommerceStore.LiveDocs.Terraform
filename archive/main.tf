locals {
  prefix = "ecommercestore-livedocs"
  tags = {
    application = "EcommerceStore"
    component   = "LiveDocs"
    environment = var.environment
    managed_by  = "Terraform"
    lifecycle   = "persistent-archive"
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "archive" {
  name     = "rg-${local.prefix}-archive-${var.environment}"
  location = var.location
  tags     = local.tags
  lifecycle { prevent_destroy = true }
}

resource "azurerm_storage_account" "archive" {
  name                            = "stecld${var.environment}${var.name_suffix}"
  resource_group_name             = azurerm_resource_group.archive.name
  location                        = azurerm_resource_group.archive.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access           = "Enabled"
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }

  lifecycle { prevent_destroy = true }
}

resource "azurerm_storage_container" "archive" {
  name                  = "livedocs"
  storage_account_id    = azurerm_storage_account.archive.id
  container_access_type = "private"
  lifecycle { prevent_destroy = true }
}

resource "azurerm_user_assigned_identity" "products_writer" {
  name                = "id-products-livedocs-writer-${var.environment}"
  resource_group_name = azurerm_resource_group.archive.name
  location            = azurerm_resource_group.archive.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "reader" {
  name                = "id-livedocs-archive-reader-${var.environment}"
  resource_group_name = azurerm_resource_group.archive.name
  location            = azurerm_resource_group.archive.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "products_writer" {
  scope                            = azurerm_storage_container.archive.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.products_writer.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "reader" {
  scope                            = azurerm_storage_container.archive.id
  role_definition_name             = "Storage Blob Data Reader"
  principal_id                     = azurerm_user_assigned_identity.reader.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "operator" {
  count                = var.operator_object_id == null ? 0 : 1
  scope                = azurerm_storage_container.archive.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.operator_object_id
}

resource "azurerm_federated_identity_credential" "products_writer" {
  name                      = "github-products-master"
  user_assigned_identity_id = azurerm_user_assigned_identity.products_writer.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:MichalBoczula/ProductsCatalog:ref:refs/heads/master"
}

resource "azurerm_federated_identity_credential" "reader" {
  for_each                  = var.enable_reader_federation ? toset(["livedocs-archive-build", "livedocs-archive-pr"]) : toset([])
  name                      = "github-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.reader.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:MichalBoczula/ECommerceStore.LiveDocs:environment:${each.value}"
}
