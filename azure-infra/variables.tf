# ---------------------------------------------------------------------------
# Core naming / placement
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the Azure resource group that will hold all fleet resources."
  type        = string
  default     = "rpi-fleet-rg"
}

variable "location" {
  description = "Azure Government region for all resources. Supported values: usgovarizona, usgovvirginia, usgovtexas."
  type        = string
  default     = "usgovarizona"
}

variable "prefix" {
  description = "Short lowercase alphanumeric prefix (max 8 chars) used to build unique resource names."
  type        = string
  default     = "rpifleet"

  validation {
    condition     = can(regex("^[a-z0-9]{1,8}$", var.prefix))
    error_message = "prefix must be 1–8 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project    = "raspberry-pi-arc"
    managed-by = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Container Registry
# ---------------------------------------------------------------------------

variable "acr_sku" {
  description = "Azure Container Registry SKU. Basic is sufficient for development; Standard or Premium adds geo-replication."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard, or Premium."
  }
}

# ---------------------------------------------------------------------------
# App Service (web app)
# ---------------------------------------------------------------------------

variable "web_app_sku" {
  description = "App Service Plan SKU for the web application (e.g. B1, B2, P1v3)."
  type        = string
  default     = "B1"
}

variable "web_app_docker_image" {
  description = "Initial Docker image reference for the web App Service (repo/image:tag). Defaults to a placeholder; update after publishing to ACR."
  type        = string
  default     = "mcr.microsoft.com/appsvc/staticsite:latest"
}

# ---------------------------------------------------------------------------
# Cosmos DB
# ---------------------------------------------------------------------------

variable "cosmos_db_name" {
  description = "Name of the Cosmos DB SQL database."
  type        = string
  default     = "fleet"
}

variable "cosmos_serverless" {
  description = "When true, provision Cosmos DB in serverless capacity mode (pay-per-request). Set false to use provisioned throughput."
  type        = bool
  default     = true
}

variable "cosmos_provisioned_throughput" {
  description = "Request units per second when cosmos_serverless = false."
  type        = number
  default     = 400
}

# ---------------------------------------------------------------------------
# Service Bus
# ---------------------------------------------------------------------------

variable "servicebus_sku" {
  description = "Service Bus namespace SKU. Must be Standard or Premium to support topics."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.servicebus_sku)
    error_message = "servicebus_sku must be Standard or Premium (topics are not available on Basic)."
  }
}

# ---------------------------------------------------------------------------
# Key Vault
# ---------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)."
  type        = string
  default     = "standard"
}
