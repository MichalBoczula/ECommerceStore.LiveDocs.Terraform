mock_provider "azurerm" {
  override_during = plan
}

override_data {
  target          = data.azurerm_client_config.current
  override_during = plan
  values = {
    tenant_id = "22222222-2222-2222-2222-222222222222"
  }
}

override_resource {
  target          = azurerm_storage_account.archive
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-livedocs-archive-dev/providers/Microsoft.Storage/storageAccounts/steclddevdemo01"
  }
}

override_resource {
  target          = azurerm_storage_container.archive
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-livedocs-archive-dev/providers/Microsoft.Storage/storageAccounts/steclddevdemo01/blobServices/default/containers/livedocs"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.products_writer
  override_during = plan
  values = {
    id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-livedocs-archive-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-products-livedocs-writer-dev"
    principal_id = "33333333-3333-3333-3333-333333333333"
    client_id    = "44444444-4444-4444-4444-444444444444"
  }
}

override_resource {
  target          = azurerm_user_assigned_identity.reader
  override_during = plan
  values = {
    id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-livedocs-archive-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-livedocs-archive-reader-dev"
    principal_id = "55555555-5555-5555-5555-555555555555"
    client_id    = "66666666-6666-6666-6666-666666666666"
  }
}

# Set every input so local deployment tfvars cannot leak into mocked scenarios.
variables {
  subscription_id          = "11111111-1111-1111-1111-111111111111"
  environment              = "dev"
  name_suffix              = "demo01"
  location                 = "northeurope"
  enable_reader_federation = false
  operator_object_id       = null
}

run "private_persistent_archive" {
  command = plan
  assert {
    condition = (
      azurerm_resource_group.archive.name == "rg-ecommercestore-livedocs-archive-dev" &&
      azurerm_storage_account.archive.name == "steclddevdemo01" &&
      azurerm_storage_account.archive.account_replication_type == "LRS" &&
      !azurerm_storage_account.archive.shared_access_key_enabled &&
      !azurerm_storage_account.archive.allow_nested_items_to_be_public &&
      azurerm_storage_account.archive.https_traffic_only_enabled &&
      azurerm_storage_container.archive.name == "livedocs" &&
      azurerm_storage_container.archive.container_access_type == "private" &&
      azurerm_storage_account.archive.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.archive.blob_properties[0].delete_retention_policy[0].days == 30 &&
      azurerm_storage_account.archive.blob_properties[0].container_delete_retention_policy[0].days == 30
    )
    error_message = "Archive bundles need a dedicated private Entra-only LRS account with recovery retention."
  }
  assert {
    condition = (
      azurerm_role_assignment.products_writer.scope == azurerm_storage_container.archive.id &&
      azurerm_role_assignment.reader.scope == azurerm_storage_container.archive.id &&
      azurerm_role_assignment.products_writer.role_definition_name == "Storage Blob Data Contributor" &&
      azurerm_role_assignment.reader.role_definition_name == "Storage Blob Data Reader" &&
      azurerm_role_assignment.products_writer.principal_id == azurerm_user_assigned_identity.products_writer.principal_id &&
      azurerm_role_assignment.reader.principal_id == azurerm_user_assigned_identity.reader.principal_id
    )
    error_message = "CI permissions must be container-scoped with separate writer and read-only identities."
  }
  assert {
    condition = (
      azurerm_federated_identity_credential.products_writer.subject == "repo:MichalBoczula/ProductsCatalog:ref:refs/heads/master" &&
      azurerm_federated_identity_credential.products_writer.issuer == "https://token.actions.githubusercontent.com" &&
      one(azurerm_federated_identity_credential.products_writer.audience) == "api://AzureADTokenExchange" &&
      length(azurerm_federated_identity_credential.reader) == 0 &&
      length(azurerm_role_assignment.operator) == 0 &&
      !output.archive_configuration.reader_federation_enabled
    )
    error_message = "Writer trust is Products master only; reader trust stays disabled until protected environments exist."
  }
}

run "protected_environment_readers" {
  command = plan
  variables {
    enable_reader_federation = true
  }
  assert {
    condition = (
      length(azurerm_federated_identity_credential.reader) == 2 &&
      azurerm_federated_identity_credential.reader["livedocs-archive-build"].subject == "repo:MichalBoczula/ECommerceStore.LiveDocs:environment:livedocs-archive-build" &&
      azurerm_federated_identity_credential.reader["livedocs-archive-pr"].subject == "repo:MichalBoczula/ECommerceStore.LiveDocs:environment:livedocs-archive-pr" &&
      output.archive_configuration.products_writer_client_id == "44444444-4444-4444-4444-444444444444" &&
      output.archive_configuration.reader_client_id == "66666666-6666-6666-6666-666666666666"
    )
    error_message = "Reader trust must use exact protected environment subjects and match workflow client IDs."
  }
}

run "operator_read_only" {
  command = plan
  variables {
    operator_object_id = "77777777-7777-7777-7777-777777777777"
  }
  assert {
    condition = (
      azurerm_role_assignment.operator[0].scope == azurerm_storage_container.archive.id &&
      azurerm_role_assignment.operator[0].role_definition_name == "Storage Blob Data Reader"
    )
    error_message = "Optional operator verification must not add a broad storage writer."
  }
}

run "maximum_storage_name" {
  command = plan
  variables {
    environment = "prod"
    name_suffix = "abcd1234"
  }
  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", azurerm_storage_account.archive.name))
    error_message = "The longest supported archive name must fit Azure's storage limits."
  }
}

run "reject_subscription_name" {
  command = plan
  variables { subscription_id = "Portfolio" }
  expect_failures = [var.subscription_id]
}

run "reject_suffix" {
  command = plan
  variables { name_suffix = "INVALID-SUFFIX" }
  expect_failures = [var.name_suffix]
}

run "reject_environment" {
  command = plan
  variables { environment = "development" }
  expect_failures = [var.environment]
}

run "reject_operator_email" {
  command = plan
  variables { operator_object_id = "mike@example.com" }
  expect_failures = [var.operator_object_id]
}
