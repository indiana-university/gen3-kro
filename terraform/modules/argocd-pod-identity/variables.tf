variable "create" {
  description = "Determines whether to create the ArgoCD pod identity"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "has_inline_policy" {
  description = "Whether to attach inline policies"
  type        = bool
  default     = true
}

variable "source_policy_documents" {
  description = "List of IAM policy documents to merge into the custom policy"
  type        = list(string)
  default     = []
}

variable "override_policy_documents" {
  description = "List of IAM policy documents to override the custom policy"
  type        = list(string)
  default     = []
}

variable "policy_arns" {
  description = "Map of policy ARNs to attach to the pod identity"
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
