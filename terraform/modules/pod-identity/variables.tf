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
# Pre-loaded IAM Policy Configuration (from external iam-policy module)
###################################################################################################################################################
variable "loaded_inline_policy_document" {
  description = "Pre-loaded inline policy document from iam-policy module"
  type        = string
  default     = null
}

variable "loaded_override_policy_documents" {
  description = "Pre-loaded override policy documents from iam-policy module"
  type        = list(string)
  default     = []
}

variable "loaded_managed_policy_arns" {
  description = "Pre-loaded managed policy ARNs from iam-policy module"
  type        = map(string)
  default     = {}
}

variable "has_loaded_inline_policy" {
  description = "Whether pre-loaded inline policy exists"
  type        = bool
  default     = false
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
