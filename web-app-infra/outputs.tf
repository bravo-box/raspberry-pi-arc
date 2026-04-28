output "app_service_url" {
  description = "Default hostname of the App Service web application."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "function_app_url" {
  description = "Default hostname of the Azure Function App."
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "cosmos_db_endpoint" {
  description = "Endpoint URI for the Cosmos DB account."
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "storage_account_endpoint" {
  description = "Primary blob service endpoint for the images storage account."
  value       = azurerm_storage_account.images.primary_blob_endpoint
}

output "servicebus_namespace_fqdn" {
  description = "Fully-qualified domain name of the Service Bus namespace."
  value       = "${azurerm_servicebus_namespace.main.name}.servicebus.usgovcloudapi.net"
}

output "container_registry_login_server" {
  description = "Login server URL for Azure Container Registry."
  value       = azurerm_container_registry.main.login_server
}
