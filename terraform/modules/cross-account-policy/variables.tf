variable "create" {
  description = "Whether to create the cross-account policy"
  type        = bool
  default     = true
}

variable "service_name" {
  description = "Service name (e.g., 'iam', 'ec2', 'eks', 'external_secrets')"
  type        = string
}

variable "hub_pod_identity_role_arn" {
  description = "ARN of the hub pod identity IAM role to attach the policy to"
  type        = string
}

variable "spoke_role_arns" {
  description = "List of spoke role ARNs that the hub pod identity can assume"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
