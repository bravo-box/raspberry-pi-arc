# ---------------------------------------------------------------------------
# Caller identity – used for Key Vault access policies and Cosmos DB RBAC.
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Random suffix – appended to globally-unique resource names.
# ---------------------------------------------------------------------------
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  # Short suffix for resource names that have strict length limits.
  sfx = random_string.suffix.result
  # Common tag map merged with caller-supplied tags.
  tags = merge(var.tags, { environment = terraform.workspace })
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "fleet" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "fleet" {
  name                = "${var.prefix}acr${local.sfx}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  sku                 = var.acr_sku
  admin_enabled       = true
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "fleet" {
  name                        = "${var.prefix}kv${local.sfx}"
  resource_group_name         = azurerm_resource_group.fleet.name
  location                    = azurerm_resource_group.fleet.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = var.key_vault_sku
  purge_protection_enabled    = false
  soft_delete_retention_days  = 7
  enable_rbac_authorization   = false
  tags                        = local.tags

  # Grant the caller (the identity running Terraform) full access so secrets
  # can be written during provisioning.
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Backup", "Restore", "Recover", "Purge"
    ]
    key_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Recover", "Purge"
    ]
    certificate_permissions = [
      "Get", "List", "Create", "Delete", "Update", "Recover", "Purge"
    ]
  }
}

# ---------------------------------------------------------------------------
# Azure Cosmos DB (SQL / Core API)
# ---------------------------------------------------------------------------
resource "azurerm_cosmosdb_account" "fleet" {
  name                = "${var.prefix}cosmos${local.sfx}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  tags                = local.tags

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.fleet.location
    failover_priority = 0
  }

  dynamic "capabilities" {
    for_each = var.cosmos_serverless ? ["EnableServerless"] : []
    content {
      name = capabilities.value
    }
  }
}

resource "azurerm_cosmosdb_sql_database" "fleet" {
  name                = var.cosmos_db_name
  resource_group_name = azurerm_resource_group.fleet.name
  account_name        = azurerm_cosmosdb_account.fleet.name

  # throughput is omitted in serverless mode (would cause an error).
  dynamic "autoscale_settings" {
    for_each = var.cosmos_serverless ? [] : [1]
    content {
      max_throughput = var.cosmos_provisioned_throughput
    }
  }
}

# Container: devices – one document per registered Pi device.
resource "azurerm_cosmosdb_sql_container" "devices" {
  name                = "devices"
  resource_group_name = azurerm_resource_group.fleet.name
  account_name        = azurerm_cosmosdb_account.fleet.name
  database_name       = azurerm_cosmosdb_sql_database.fleet.name
  partition_key_path  = "/id"

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/*" }
    excluded_path { path = "/\"_etag\"/?" }
  }
}

# Container: images – one document per uploaded camera image.
resource "azurerm_cosmosdb_sql_container" "images" {
  name                = "images"
  resource_group_name = azurerm_resource_group.fleet.name
  account_name        = azurerm_cosmosdb_account.fleet.name
  database_name       = azurerm_cosmosdb_sql_database.fleet.name
  partition_key_path  = "/hostName"

  indexing_policy {
    indexing_mode = "consistent"

    included_path { path = "/*" }
    excluded_path { path = "/\"_etag\"/?" }
  }
}

# ---------------------------------------------------------------------------
# Azure Service Bus
# Topics required by the camera-app:
#   TaskCamera    – triggers photo capture on the Pi
#   photo-upload  – upload notification published by the Pi
#   photo-processed – acknowledgement sent by the cloud function
# ---------------------------------------------------------------------------
resource "azurerm_servicebus_namespace" "fleet" {
  name                = "${var.prefix}sb${local.sfx}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  sku                 = var.servicebus_sku
  tags                = local.tags
}

# --- TaskCamera topic -------------------------------------------------------
resource "azurerm_servicebus_topic" "task_camera" {
  name         = "TaskCamera"
  namespace_id = azurerm_servicebus_namespace.fleet.id
}

# Subscription consumed by the Pi's camera-service container.
resource "azurerm_servicebus_subscription" "task_camera_camera_service" {
  name               = "camera-service"
  topic_id           = azurerm_servicebus_topic.task_camera.id
  max_delivery_count = 5
}

# Subscription consumed by the cloud-side Azure Function for audit logging.
resource "azurerm_servicebus_subscription" "task_camera_cloud_monitor" {
  name               = "cloud-monitor"
  topic_id           = azurerm_servicebus_topic.task_camera.id
  max_delivery_count = 5
}

# --- photo-upload topic -----------------------------------------------------
resource "azurerm_servicebus_topic" "photo_upload" {
  name         = "photo-upload"
  namespace_id = azurerm_servicebus_namespace.fleet.id
}

# Subscription consumed by the cloud-side Azure Function.
resource "azurerm_servicebus_subscription" "photo_upload_cloud_processor" {
  name               = "cloud-processor"
  topic_id           = azurerm_servicebus_topic.photo_upload.id
  max_delivery_count = 5
}

# --- photo-processed topic --------------------------------------------------
resource "azurerm_servicebus_topic" "photo_processed" {
  name         = "photo-processed"
  namespace_id = azurerm_servicebus_namespace.fleet.id
}

# Subscription consumed by the Pi's file-service container for ack-triggered
# local file deletion.
resource "azurerm_servicebus_subscription" "photo_processed_file_service" {
  name               = "file-service"
  topic_id           = azurerm_servicebus_topic.photo_processed.id
  max_delivery_count = 5
}

# Subscription consumed by the cloud-side Azure Function for audit logging.
resource "azurerm_servicebus_subscription" "photo_processed_cloud_audit" {
  name               = "cloud-audit"
  topic_id           = azurerm_servicebus_topic.photo_processed.id
  max_delivery_count = 5
}

# ---------------------------------------------------------------------------
# Storage Account
# Used for: (1) Azure Function App host storage; (2) photo blob container.
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "fleet" {
  name                     = "${var.prefix}st${local.sfx}"
  resource_group_name      = azurerm_resource_group.fleet.name
  location                 = azurerm_resource_group.fleet.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.tags
}

# Blob container that stores photos uploaded by the Pi fleet.
resource "azurerm_storage_container" "photos" {
  name                  = "photos"
  storage_account_name  = azurerm_storage_account.fleet.name
  container_access_type = "private"
}

# ---------------------------------------------------------------------------
# Application Insights (shared by web app and function app)
# ---------------------------------------------------------------------------
resource "azurerm_application_insights" "fleet" {
  name                = "${var.prefix}-appinsights"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  application_type    = "web"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# App Service Plan – Web Application
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "web" {
  name                = "${var.prefix}-web-plan"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  os_type             = "Linux"
  sku_name            = var.web_app_sku
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Linux Web App – container-hosted C# dashboard
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "fleet" {
  name                = "${var.prefix}-webapp-${local.sfx}"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  service_plan_id     = azurerm_service_plan.web.id
  https_only          = true
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true

    application_stack {
      docker_image_name        = var.web_app_docker_image
      docker_registry_url      = "https://${azurerm_container_registry.fleet.login_server}"
      docker_registry_username = azurerm_container_registry.fleet.admin_username
      docker_registry_password = azurerm_container_registry.fleet.admin_password
    }
  }

  app_settings = {
    WEBSITES_PORT                      = "8080"
    APPINSIGHTS_INSTRUMENTATIONKEY     = azurerm_application_insights.fleet.instrumentation_key
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"

    # Cosmos DB
    CosmosDb__Endpoint    = azurerm_cosmosdb_account.fleet.endpoint
    CosmosDb__AccountKey  = azurerm_cosmosdb_account.fleet.primary_key
    CosmosDb__DatabaseName = var.cosmos_db_name

    # Storage – account name used to build the Gov endpoint; access is via managed identity.
    Storage__AccountName    = azurerm_storage_account.fleet.name
    Storage__PhotoContainer = azurerm_storage_container.photos.name
  }
}

# Grant the web app's managed identity 'Storage Blob Data Reader' on the storage account.
# Required to read blobs and to generate User Delegation SAS tokens via the managed identity.
resource "azurerm_role_assignment" "web_app_storage_reader" {
  scope                = azurerm_storage_account.fleet.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_web_app.fleet.identity[0].principal_id
}

# Grant the web app's managed identity 'Storage Blob Data Delegator' on the storage account.
# Required to call GetUserDelegationKey so the app can mint user-delegation SAS tokens
# without needing the storage account key.
resource "azurerm_role_assignment" "web_app_storage_delegator" {
  scope                = azurerm_storage_account.fleet.id
  role_definition_name = "Storage Blob Data Delegator"
  principal_id         = azurerm_linux_web_app.fleet.identity[0].principal_id
}

# Grant the web app's managed identity access to Key Vault secrets.
resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = azurerm_key_vault.fleet.id
  tenant_id    = azurerm_linux_web_app.fleet.identity[0].tenant_id
  object_id    = azurerm_linux_web_app.fleet.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# ---------------------------------------------------------------------------
# App Service Plan – Function App (Consumption / Y1)
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "functions" {
  name                = "${var.prefix}-func-plan"
  resource_group_name = azurerm_resource_group.fleet.name
  location            = azurerm_resource_group.fleet.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Linux Function App – processes Service Bus messages
# ---------------------------------------------------------------------------
resource "azurerm_linux_function_app" "fleet" {
  name                       = "${var.prefix}-func-${local.sfx}"
  resource_group_name        = azurerm_resource_group.fleet.name
  location                   = azurerm_resource_group.fleet.location
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.fleet.name
  storage_account_access_key = azurerm_storage_account.fleet.primary_access_key
  https_only                 = true
  tags                       = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_insights_key               = azurerm_application_insights.fleet.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.fleet.connection_string

    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "dotnet-isolated"
    WEBSITE_RUN_FROM_PACKAGE = "1"

    # Service Bus connection used by trigger bindings.
    ServiceBusConnection = azurerm_servicebus_namespace.fleet.default_primary_connection_string

    # Cosmos DB output binding
    CosmosDb__Endpoint     = azurerm_cosmosdb_account.fleet.endpoint
    CosmosDb__AccountKey   = azurerm_cosmosdb_account.fleet.primary_key
    CosmosDb__DatabaseName = var.cosmos_db_name

    APPINSIGHTS_INSTRUMENTATIONKEY = azurerm_application_insights.fleet.instrumentation_key
  }
}

# Grant the function app's managed identity access to Key Vault secrets.
resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = azurerm_key_vault.fleet.id
  tenant_id    = azurerm_linux_function_app.fleet.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.fleet.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# ---------------------------------------------------------------------------
# Store the Service Bus connection string in Key Vault
# (Pi devices read their credentials from Key Vault at boot time)
# ---------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "servicebus_connection" {
  name         = "ServiceBusConnectionString"
  value        = azurerm_servicebus_namespace.fleet.default_primary_connection_string
  key_vault_id = azurerm_key_vault.fleet.id
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "cosmos_key" {
  name         = "CosmosDbAccountKey"
  value        = azurerm_cosmosdb_account.fleet.primary_key
  key_vault_id = azurerm_key_vault.fleet.id
  tags         = local.tags
}

resource "azurerm_key_vault_secret" "storage_key" {
  name         = "StorageAccountKey"
  value        = azurerm_storage_account.fleet.primary_access_key
  key_vault_id = azurerm_key_vault.fleet.id
  tags         = local.tags
}
