###############################################################################
# Azure Spoke Role Module
# Creates Azure role assignments for cross-subscription access
###############################################################################

variable "create" {
  description = "Whether to create the role assignment"
  type        = bool
}

variable "spoke_alias" {
  description = "Spoke alias"
  type        = string
}

variable "service_name" {
  description = "Service name"
  type        = string
}

variable "hub_managed_identity_principal_id" {
  description = "Principal ID of hub managed identity"
  type        = string
}

variable "scope" {
  description = "Scope for role assignment (subscription or resource group ID)"
  type        = string
}

variable "role_definition_name" {
  description = "Built-in role name (e.g., 'Key Vault Secrets User')"
  type        = string
}

variable "custom_role_definition_id" {
  description = "Custom role definition ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
}
