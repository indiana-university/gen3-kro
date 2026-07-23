variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "csoc_source_role_arn" {
  description = "Exact CSOC ACK controller role ARN allowed to assume spoke access roles"
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+", var.csoc_source_role_arn))
    error_message = "csoc_source_role_arn must be an exact IAM role ARN."
  }
}

variable "manual_operator_role_arns" {
  description = "Exact CSOC operator role ARNs allowed to assume spoke access roles for manual operations."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.manual_operator_role_arns :
      can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+", arn))
    ])
    error_message = "manual_operator_role_arns must contain exact IAM role ARNs."
  }
}

variable "roles" {
  description = "Map of ACK IAM roles to create in the spoke account. Key is role key, value is configuration object."
  type = map(object({
    enabled          = bool
    managed_policies = list(string)
    custom_policies  = optional(list(any), [])
    resource_types = optional(list(object({
      group   = string
      version = string
      kind    = string
    })), [])
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all IAM resources"
  type        = map(string)
  default     = {}
}

variable "spoke_alias" {
  description = "Alias for the spoke account (e.g., 'spoke1', 'spoke2')"
  type        = string
}
