###############################################################################
# GCP Workload Identity Module
# Creates service account and workload identity binding
###############################################################################

variable "create" {
  description = "Whether to create workload identity"
  type        = bool
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "service_account_name" {
  description = "Name of the GCP service account"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_account_k8s" {
  description = "Kubernetes service account name"
  type        = string
}

variable "roles" {
  description = "List of IAM roles to grant"
  type        = list(string)
}

variable "custom_role_id" {
  description = "Custom role ID (optional)"
  type        = string
}
