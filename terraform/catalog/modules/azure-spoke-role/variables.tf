###############################################################################
# Azure Spoke Role Module
# Creates Azure role assignments for cross-subscription access
###############################################################################

variable "create" {
  description = "Whether to create the role assignment"
  type        = bool
}

variable "override_id" {
  description = "Override identity ID (use existing identity instead of creating new role assignment). When set, create is ignored and this value is returned."
  type        = string
  default     = null
}

variable "csoc_managed_identity_principal_id" {
  description = "Principal ID of CSOC managed identity"
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
