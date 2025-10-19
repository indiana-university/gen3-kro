###################################################################################################################################################
# Generic Pod Identity Module Variables
# Universal configuration for ACK, addons, ArgoCD, and custom services
###################################################################################################################################################

variable "create" {
  description = "Whether to create the pod identity"
  type        = bool
  default     = true
}

###################################################################################################################################################
# Service Identification
###################################################################################################################################################
variable "service_type" {
  description = "Type of service (acks, addons)"
  type        = string
  validation {
    condition     = contains(["acks", "addons"], var.service_type)
    error_message = "service_type must be one of: acks, addons"
  }
}

variable "service_name" {
  description = "Name of the service (e.g., 'iam', 'ec2' for ACK; 'aws-load-balancer-controller' for addon)"
  type        = string
}

variable "context" {
  description = "Context for policy loading (hub or spoke alias). Will be overridden by tags.Spoke if present"
  type        = string
  default     = "hub"
}

###################################################################################################################################################
# Cluster and Namespace Configuration
###################################################################################################################################################
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name"
  type        = string
}

###################################################################################################################################################
# IAM Policy Loading Configuration
###################################################################################################################################################
variable "iam_policy_repo_url" {
  description = "URL of the Git repository containing IAM policy files"
  type        = string
  default     = ""
}

variable "iam_policy_branch" {
  description = "Branch of the Git repository to use"
  type        = string
  default     = "main"
}

variable "iam_policy_base_path" {
  description = "Base path within the Git repository where policy files are located"
  type        = string
  default     = "iam"
}

variable "iam_raw_base_url" {
  description = "Raw file base URL for fetching IAM policies via HTTP (e.g., https://raw.githubusercontent.com/org/repo/branch)"
  type        = string
  default     = ""
}

variable "repo_root_path" {
  description = "Local filesystem path to the repository root (alternative to Git)"
  type        = string
  default     = ""
}

###################################################################################################################################################
# Custom Policy Configuration (alternative to filesystem loading)
###################################################################################################################################################
variable "custom_inline_policy" {
  description = "Custom inline policy JSON document (overrides filesystem loading)"
  type        = string
  default     = null
}

variable "custom_managed_arns" {
  description = "Map of custom managed policy ARNs to attach (overrides filesystem loading)"
  type        = map(string)
  default     = {}
}

variable "additional_policy_arns" {
  description = "Additional managed policy ARNs to attach (merged with filesystem or custom policies)"
  type        = map(string)
  default     = {}
}

variable "cross_account_policy_json" {
  description = "Additional cross-account policy JSON to merge with inline policies"
  type        = string
  default     = null
}

###################################################################################################################################################
# Pod Identity Configuration
###################################################################################################################################################
variable "trust_policy_conditions" {
  description = "Additional trust policy conditions for the IAM role"
  type        = list(any)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
