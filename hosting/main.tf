locals {
  shared_environment = var.shared_environment == null ? {
    name                = "cae-ecommercestore-products-${var.environment}"
    resource_group_name = "rg-ecommercestore-products-${var.environment}"
  } : var.shared_environment
  tags = {
    application = "EcommerceStore"
    component   = "LiveDocs"
    environment = var.environment
    managed_by  = "Terraform"
    purpose     = "portfolio"
  }
}

data "azurerm_container_app_environment" "shared" {
  name                = local.shared_environment.name
  resource_group_name = local.shared_environment.resource_group_name
}

resource "azurerm_resource_group" "hosting" {
  name     = "rg-ecommercestore-livedocs-${var.environment}"
  location = data.azurerm_container_app_environment.shared.location
  tags     = local.tags
}

resource "azurerm_container_app" "livedocs" {
  name                         = "ca-ecommercestore-livedocs-${var.environment}"
  resource_group_name          = azurerm_resource_group.hosting.name
  container_app_environment_id = data.azurerm_container_app_environment.shared.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = local.tags

  ingress {
    external_enabled           = var.external_ingress_enabled
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = 1
    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }
    container {
      name   = "livedocs"
      image  = var.livedocs_image
      cpu    = 0.25
      memory = "0.5Gi"

      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health/live"
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 30
      }
      liveness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health/live"
        interval_seconds        = 30
        timeout                 = 3
        failure_count_threshold = 3
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health/ready"
        interval_seconds        = 10
        timeout                 = 3
        success_count_threshold = 1
        failure_count_threshold = 3
      }
    }
  }

  lifecycle {
    precondition {
      condition = !var.external_ingress_enabled || (
        !data.azurerm_container_app_environment.shared.internal_load_balancer_enabled &&
        data.azurerm_container_app_environment.shared.public_network_access == "Enabled"
      )
      error_message = "Public documentation requires a publicly reachable ACA environment. Keep ingress internal for an isolated environment."
    }
  }
}
