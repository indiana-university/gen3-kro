variable "create" {
  description = "Whether to create the cross-account policy"
  type        = bool
}

variable "service_name" {
  description = "Service name (e.g., 'iam', 'ec2', 'eks', 'external_secrets')"
  type        = string
}

variable "csoc_pod_identity_role_arn" {
  description = "ARN of the CSOC pod identity IAM role to attach the policy to"
  type        = string
}

variable "spoke_role_arns" {
  description = "List of spoke role ARNs that the CSOC pod identity can assume"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
