###############################################################################
# Azure Resource Group Module
# Creates a resource group for Azure resources
###############################################################################

variable "create" {
  description = "Whether to create the resource group"
  type        = bool
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string
}

variable "tags" {
  description = "Tags to apply to the resource group"
  type        = map(string)
}
