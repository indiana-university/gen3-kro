###############################################################################
# Azure Managed Identity Module
# Creates user-assigned managed identity for workload identity
###############################################################################

variable "create" {
  description = "Whether to create the managed identity"
  type        = bool
}

variable "identity_name" {
  description = "Name of the managed identity"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL from AKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace (single mode)"
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name"
  type        = string
}

variable "role_definition_id" {
  description = "Custom role definition ID (optional)"
  type        = string
}

variable "scope" {
  description = "Scope for role assignment"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
