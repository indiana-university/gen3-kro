variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "csoc_account_id" {
  description = "CSOC AWS account ID (for trust policy on spoke workload roles)"
  type        = string
}

variable "csoc_source_role_arn" {
  description = "Exact CSOC source role ARN allowed to assume spoke workload roles"
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+", var.csoc_source_role_arn))
    error_message = "csoc_source_role_arn must be an exact IAM role ARN."
  }
}

variable "allow_devcontainer_assume_role" {
  description = "Whether to retain devcontainer role trust for manual cleanup operations"
  type        = bool
  default     = false
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
