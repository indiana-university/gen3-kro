variable "create" {
  description = "Determines whether to create the cross-account policy"
  type        = bool
  default     = true
}

variable "spoke_role_arns" {
  description = "List of ARNs of IAM roles in spoke accounts that can be assumed"
  type        = list(string)
  default     = []
}

variable "additional_statements" {
  description = "Additional IAM policy statements to include"
  type = list(object({
    sid       = string
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}
