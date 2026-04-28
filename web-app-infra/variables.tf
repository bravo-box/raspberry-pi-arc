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
  description = "Full container image reference for the web app (e.g. registry/image:tag)."
  type        = string
  default     = "rpi-arc-webapp:latest"
}
