# ── Cosmos DB roles ───────────────────────────────────────────────────────────
# Built-in Cosmos DB role IDs are fixed GUIDs.
locals {
  cosmos_data_reader_role_id      = "00000000-0000-0000-0000-000000000001"
  cosmos_data_contributor_role_id = "00000000-0000-0000-0000-000000000002"
}

# App Service → Cosmos DB Built-in Data Reader
resource "azurerm_cosmosdb_sql_role_assignment" "webapp_cosmos_reader" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/${local.cosmos_data_reader_role_id}"
  principal_id        = azurerm_linux_web_app.main.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.main.id

  depends_on = [azurerm_linux_web_app.main]
}

# Function App → Cosmos DB Built-in Data Contributor
resource "azurerm_cosmosdb_sql_role_assignment" "funcapp_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/${local.cosmos_data_contributor_role_id}"
  principal_id        = azurerm_linux_function_app.main.identity[0].principal_id
  scope               = azurerm_cosmosdb_account.main.id

  depends_on = [azurerm_linux_function_app.main]
}

# ── Storage Blob roles (images account) ──────────────────────────────────────

# Function App → Storage Blob Data Contributor
resource "azurerm_role_assignment" "funcapp_storage_blob_contributor" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# App Service → Storage Blob Data Reader
resource "azurerm_role_assignment" "webapp_storage_blob_reader" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_web_app.main]
}

# ── Service Bus roles ─────────────────────────────────────────────────────────

# App Service → Azure Service Bus Data Owner
resource "azurerm_role_assignment" "webapp_servicebus_owner" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_web_app.main]
}

# Function App → Azure Service Bus Data Owner
resource "azurerm_role_assignment" "funcapp_servicebus_owner" {
  scope                = azurerm_servicebus_namespace.main.id
  role_definition_name = "Azure Service Bus Data Owner"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}

# ── ACR pull roles ────────────────────────────────────────────────────────────

# App Service → AcrPull
resource "azurerm_role_assignment" "webapp_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_web_app.main]
}

# Function App → AcrPull
resource "azurerm_role_assignment" "funcapp_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id

  depends_on = [azurerm_linux_function_app.main]
}
