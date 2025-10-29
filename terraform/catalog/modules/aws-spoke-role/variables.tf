variable "create" {
  description = "Whether to create the spoke account IAM role"
  type        = bool
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_name" {
  description = "Service name (e.g., 's3', 'argocd', 'external_secrets')"
  type        = string
}

variable "spoke_alias" {
  description = "Alias for the spoke account (used in role name)"
  type        = string
}

variable "csoc_pod_identity_role_arn" {
  description = "ARN of the csoc pod identity IAM role that will assume this spoke role"
  type        = string
}

###################################################################################################################################################
# Policy Inputs (from ack-iam-policy module)
###################################################################################################################################################
variable "combined_policy_json" {
  description = "Combined policy document JSON (if inline policies exist)"
  type        = string
  default     = null
}

variable "policy_arns" {
  description = "Map of managed policy ARNs to attach"
  type        = map(string)
  default     = {}
}

variable "has_inline_policy" {
  description = "Whether inline policies are available"
  type        = bool
  default     = false
}

variable "has_managed_policy" {
  description = "Whether managed policy ARNs are available"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
