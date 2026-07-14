variable "source_role_name" {
  description = "Name of the CSOC source role receiving assume-spoke permissions"
  type        = string
}

variable "spoke_role_arns" {
  description = "Map of spoke aliases to exact workload role ARNs"
  type        = map(string)
  default     = {}
}

variable "policy_name" {
  description = "Inline policy name"
  type        = string
  default     = "csoc-assume-spokes"
}
