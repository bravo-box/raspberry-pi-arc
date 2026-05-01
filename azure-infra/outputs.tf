# ---------------------------------------------------------------------------
# Connection & endpoint outputs
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the provisioned resource group."
  value       = azurerm_resource_group.fleet.name
}

output "acr_login_server" {
  description = "Container Registry login server (e.g. rpifleetacrXXXXXX.azurecr.us)."
  value       = azurerm_container_registry.fleet.login_server
}

output "acr_admin_username" {
  description = "Admin username for the Container Registry."
  value       = azurerm_container_registry.fleet.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for the Container Registry."
  value       = azurerm_container_registry.fleet.admin_password
  sensitive   = true
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.fleet.vault_uri
}

output "cosmos_db_endpoint" {
  description = "Cosmos DB account endpoint."
  value       = azurerm_cosmosdb_account.fleet.endpoint
}

output "cosmos_db_primary_key" {
  description = "Cosmos DB primary account key."
  value       = azurerm_cosmosdb_account.fleet.primary_key
  sensitive   = true
}

output "servicebus_namespace_name" {
  description = "Service Bus namespace name."
  value       = azurerm_servicebus_namespace.fleet.name
}

output "servicebus_connection_string" {
  description = "Service Bus primary connection string (root manage shared access key)."
  value       = azurerm_servicebus_namespace.fleet.default_primary_connection_string
  sensitive   = true
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.fleet.name
}

output "storage_account_key" {
  description = "Storage account primary access key."
  value       = azurerm_storage_account.fleet.primary_access_key
  sensitive   = true
}

output "storage_photo_container" {
  description = "Blob container name used to store Pi camera photos."
  value       = azurerm_storage_container.photos.name
}

output "web_app_hostname" {
  description = "Public hostname of the fleet dashboard web application."
  value       = azurerm_linux_web_app.fleet.default_hostname
}

output "function_app_hostname" {
  description = "Public hostname of the fleet Azure Function App."
  value       = azurerm_linux_function_app.fleet.default_hostname
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key."
  value       = azurerm_application_insights.fleet.instrumentation_key
  sensitive   = true
}
