output "archive_configuration" {
  description = "Non-secret GitHub repository variable values and archive identifiers. Enable flags and GitHub App credentials are configured separately."
  value = {
    subscription_id           = var.subscription_id
    tenant_id                 = data.azurerm_client_config.current.tenant_id
    resource_group_name       = azurerm_resource_group.archive.name
    storage_account_name      = azurerm_storage_account.archive.name
    storage_account_id        = azurerm_storage_account.archive.id
    container_name            = azurerm_storage_container.archive.name
    container_id              = azurerm_storage_container.archive.id
    products_writer_client_id = azurerm_user_assigned_identity.products_writer.client_id
    reader_client_id          = azurerm_user_assigned_identity.reader.client_id
    reader_federation_enabled = var.enable_reader_federation
  }
}
