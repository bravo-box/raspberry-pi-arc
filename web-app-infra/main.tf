locals {
  tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }

  # Shared suffix for globally-unique resource names.
  name_suffix = "${var.project_name}-${var.environment}"
}

# Random suffix for globally-unique names (storage, cosmos, acr).
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ── Resource Group ────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}

# ── Azure Container Registry ──────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  name                = "acr${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# ── Azure Service Bus ─────────────────────────────────────────────────────────

resource "azurerm_servicebus_namespace" "main" {
  name                = "sb-${local.name_suffix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_servicebus_topic" "device_registration" {
  name         = "device-registration"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_topic" "device_commands" {
  name         = "device-commands"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_topic" "device_telemetry" {
  name         = "device-telemetry"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_topic" "device_images" {
  name         = "device-images"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_subscription" "device_registration" {
  name               = "backend-sub"
  topic_id           = azurerm_servicebus_topic.device_registration.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "device_commands" {
  name               = "backend-sub"
  topic_id           = azurerm_servicebus_topic.device_commands.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "device_telemetry" {
  name               = "backend-sub"
  topic_id           = azurerm_servicebus_topic.device_telemetry.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "device_images" {
  name               = "backend-sub"
  topic_id           = azurerm_servicebus_topic.device_images.id
  max_delivery_count = 10
}

# Registration response topic — Azure Function publishes here after assigning a GUID;
# the rpi-app listens on the rpi-sub subscription, filtered by correlation ID.
resource "azurerm_servicebus_topic" "device_registration_response" {
  name         = "device-registration-response"
  namespace_id = azurerm_servicebus_namespace.main.id
}

resource "azurerm_servicebus_subscription" "device_registration_response_rpi" {
  name               = "rpi-sub"
  topic_id           = azurerm_servicebus_topic.device_registration_response.id
  max_delivery_count = 10
}

resource "azurerm_servicebus_subscription" "device_registration_response_backend" {
  name               = "backend-sub"
  topic_id           = azurerm_servicebus_topic.device_registration_response.id
  max_delivery_count = 10
}

# ── Cosmos DB ─────────────────────────────────────────────────────────────────

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${local.name_suffix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = azurerm_resource_group.main.location
    failover_priority = 0
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = "rpi-arc"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "fleet" {
  name                = "fleet"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/id"
}

resource "azurerm_cosmosdb_sql_container" "telemetry" {
  name                = "telemetry"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/assetId"
}

resource "azurerm_cosmosdb_sql_container" "images" {
  name                = "images"
  resource_group_name = azurerm_resource_group.main.name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = "/assetId"
}

# ── Storage Account (device images) ──────────────────────────────────────────

resource "azurerm_storage_account" "images" {
  # Max 24 chars, lowercase alphanumeric only.
  name                = substr("img${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}", 0, 24)
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Key access disabled — managed-identity / RBAC access only.
  shared_access_key_enabled        = false
  allow_nested_items_to_be_public  = false
  min_tls_version                  = "TLS1_2"

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_storage_container" "device_images" {
  name                  = "device-images"
  storage_account_name  = azurerm_storage_account.images.name
  container_access_type = "private"
}

# ── App Service Plan ──────────────────────────────────────────────────────────

resource "azurerm_service_plan" "main" {
  name                = "asp-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"

  tags = local.tags
}

# ── App Service (Web App) ─────────────────────────────────────────────────────

resource "azurerm_linux_web_app" "main" {
  name                = "app-${local.name_suffix}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = true

    application_stack {
      docker_image_name   = "${azurerm_container_registry.main.login_server}/${var.container_image}"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    COSMOS_ENDPOINT            = azurerm_cosmosdb_account.main.endpoint
    COSMOS_DATABASE            = azurerm_cosmosdb_sql_database.main.name
    SERVICEBUS_FQDN            = "${azurerm_servicebus_namespace.main.name}.servicebus.usgovcloudapi.net"
    STORAGE_ACCOUNT_ENDPOINT   = azurerm_storage_account.images.primary_blob_endpoint
    ACR_LOGIN_SERVER           = azurerm_container_registry.main.login_server
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
    DOCKER_REGISTRY_SERVER_URL = "https://${azurerm_container_registry.main.login_server}"
  }

  tags = local.tags
}

# ── Function App ──────────────────────────────────────────────────────────────

resource "azurerm_storage_account" "functions" {
  name                = substr("fn${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}", 0, 24)
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}

resource "azurerm_linux_function_app" "main" {
  name                       = "func-${local.name_suffix}-${random_string.suffix.result}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.functions.name
  storage_account_access_key = azurerm_storage_account.functions.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME   = "dotnet-isolated"
    COSMOS_ENDPOINT            = azurerm_cosmosdb_account.main.endpoint
    COSMOS_DATABASE            = azurerm_cosmosdb_sql_database.main.name
    SERVICEBUS_FQDN            = "${azurerm_servicebus_namespace.main.name}.servicebus.usgovcloudapi.net"
    STORAGE_ACCOUNT_ENDPOINT   = azurerm_storage_account.images.primary_blob_endpoint
    ACR_LOGIN_SERVER           = azurerm_container_registry.main.login_server
  }

  tags = local.tags
}
