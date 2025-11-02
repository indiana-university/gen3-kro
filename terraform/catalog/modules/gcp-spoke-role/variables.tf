###############################################################################
# GCP Spoke Role Module
# Creates GCP IAM bindings for cross-project access
###############################################################################

variable "create" {
  description = "Whether to create the IAM binding"
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

variable "project_id" {
  description = "GCP project ID for the spoke"
  type        = string
}

variable "csoc_service_account_email" {
  description = "Email of CSOC service account"
  type        = string
}

variable "roles" {
  description = "List of IAM roles to grant"
  type        = list(string)
}

variable "custom_role_id" {
  description = "Custom role ID"
  type        = string
}
