variable "resource_group_name" {
  description = "Name of the resource group for application resources."
  type        = string
}

variable "location" {
  description = "Azure Government region for all resources."
  type        = string
  default     = "usgovarizona"
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "rpi-arc"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging, dev)."
  type        = string
  default     = "prod"
}

variable "container_image" {
  description = "Image repository and tag for the web app, without the registry host (e.g. 'rpi-arc-webapp:latest'). The ACR login server is prepended automatically."
  type        = string
  default     = "rpi-arc-webapp:latest"
}
