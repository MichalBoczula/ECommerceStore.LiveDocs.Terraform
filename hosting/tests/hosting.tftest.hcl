mock_provider "azurerm" {
  override_during = plan
}

override_data {
  target          = data.azurerm_container_app_environment.shared
  override_during = plan
  values = {
    id                             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-products-dev/providers/Microsoft.App/managedEnvironments/cae-ecommercestore-products-dev"
    location                       = "northeurope"
    internal_load_balancer_enabled = false
    public_network_access          = "Enabled"
  }
}

# Explicit baseline keeps deployment tfvars and TF_VAR values out of tests.
variables {
  subscription_id          = "11111111-1111-1111-1111-111111111111"
  environment              = "dev"
  shared_environment       = null
  livedocs_image           = "mb0101/ecommerce-store-livedocs@sha256:05062d11af8cba8e00f7d738037ba53efeb190db398f035cdaa8053f780394d8"
  external_ingress_enabled = false
  min_replicas             = 0
}

run "stateless_internal_host" {
  command = plan
  assert {
    condition = (
      azurerm_resource_group.hosting.name == "rg-ecommercestore-livedocs-dev" &&
      azurerm_container_app.livedocs.name == "ca-ecommercestore-livedocs-dev" &&
      azurerm_container_app.livedocs.container_app_environment_id == data.azurerm_container_app_environment.shared.id &&
      azurerm_container_app.livedocs.workload_profile_name == "Consumption" &&
      azurerm_container_app.livedocs.revision_mode == "Single" &&
      !azurerm_container_app.livedocs.ingress[0].external_enabled &&
      !azurerm_container_app.livedocs.ingress[0].allow_insecure_connections &&
      azurerm_container_app.livedocs.ingress[0].target_port == 8080 &&
      azurerm_container_app.livedocs.template[0].min_replicas == 0 &&
      azurerm_container_app.livedocs.template[0].max_replicas == 1 &&
      azurerm_container_app.livedocs.template[0].container[0].cpu == 0.25 &&
      azurerm_container_app.livedocs.template[0].container[0].memory == "0.5Gi" &&
      length(azurerm_container_app.livedocs.template[0].container[0].env) == 0 &&
      length(azurerm_container_app.livedocs.template[0].container[0].volume_mounts) == 0
    )
    error_message = "Use one small stateless app in the existing environment, without archive credentials or persistent mounts."
  }
  assert {
    condition = (
      azurerm_container_app.livedocs.template[0].container[0].startup_probe[0].path == "/health/live" &&
      azurerm_container_app.livedocs.template[0].container[0].liveness_probe[0].path == "/health/live" &&
      azurerm_container_app.livedocs.template[0].container[0].readiness_probe[0].path == "/health/ready" &&
      output.livedocs_deployment.image == var.livedocs_image
    )
    error_message = "Honor the published Nginx port/health/image contract without a SQL or archive readiness dependency."
  }
}

run "public_portfolio_demo" {
  command = plan
  variables {
    external_ingress_enabled = true
    min_replicas             = 1
  }
  assert {
    condition     = azurerm_container_app.livedocs.ingress[0].external_enabled && azurerm_container_app.livedocs.template[0].min_replicas == 1
    error_message = "A public demo must be explicit and may temporarily keep one instance ready."
  }
}

run "alternate_shared_environment" {
  command = plan
  variables {
    shared_environment = {
      name                = "cae-shared-docs"
      resource_group_name = "rg-shared-docs"
    }
  }
  assert {
    condition     = data.azurerm_container_app_environment.shared.name == "cae-shared-docs"
    error_message = "An explicit shared environment must be used only as a data lookup."
  }
}

run "reject_public_network_isolation" {
  command = plan
  variables { external_ingress_enabled = true }
  override_data {
    target = data.azurerm_container_app_environment.shared
    values = {
      id                             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-shared/providers/Microsoft.App/managedEnvironments/cae-shared"
      location                       = "northeurope"
      internal_load_balancer_enabled = true
      public_network_access          = "Disabled"
    }
  }
  expect_failures = [azurerm_container_app.livedocs]
}

run "reject_floating_image" {
  command = plan
  variables { livedocs_image = "mb0101/ecommerce-store-livedocs:latest" }
  expect_failures = [var.livedocs_image]
}

run "reject_replica_cost_increase" {
  command = plan
  variables { min_replicas = 2 }
  expect_failures = [var.min_replicas]
}

run "reject_subscription_name" {
  command = plan
  variables { subscription_id = "Portfolio" }
  expect_failures = [var.subscription_id]
}

run "reject_environment_url" {
  command = plan
  variables {
    shared_environment = {
      name                = "https://environment.example.com"
      resource_group_name = "rg-example"
    }
  }
  expect_failures = [var.shared_environment]
}
