variable "create" {
  description = "Determines whether to create the ACK pod identity"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_name" {
  description = "Name of the ACK service (e.g., s3, rds, etc.)"
  type        = string
}

variable "cross_account_policy_json" {
  description = "JSON policy document for cross-account access"
  type        = string
  default     = null
}

variable "override_policy_documents" {
  description = "List of IAM policy documents to override the default policies"
  type        = list(string)
  default     = []
}

variable "additional_policy_arns" {
  description = "Map of additional policy ARNs to attach to the pod identity"
  type        = map(string)
  default     = {}
}

variable "trust_policy_conditions" {
  description = "List of conditions to apply to the trust policy"
  type        = list(any)
  default     = []
}

variable "association_defaults" {
  description = "Default values for pod identity associations"
  type        = map(string)
  default     = {}
}

variable "associations" {
  description = "Map of pod identity associations"
  type        = map(any)
  default     = {}
}

variable "tags" {
  description = "Map of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
