output "livedocs_deployment" {
  description = "Non-secret hosting and verification targets. An internal URL is reachable only within the ACA environment."
  value = {
    subscription_id     = var.subscription_id
    resource_group_name = azurerm_resource_group.hosting.name
    name                = azurerm_container_app.livedocs.name
    id                  = azurerm_container_app.livedocs.id
    location            = azurerm_container_app.livedocs.location
    aca_environment_id  = data.azurerm_container_app_environment.shared.id
    base_url            = "https://${azurerm_container_app.livedocs.ingress[0].fqdn}"
    documentation_url   = "https://${azurerm_container_app.livedocs.ingress[0].fqdn}/livedoc/"
    image               = var.livedocs_image
    external_ingress    = var.external_ingress_enabled
    min_replicas        = var.min_replicas
  }
}
