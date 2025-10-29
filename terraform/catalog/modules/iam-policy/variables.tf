###############################################################################
# IAM Policy Module Variables (Cloud Agnostic)
###############################################################################

variable "service_name" {
  description = "Name of the service (e.g., 's3', 'ebs-csi', 'argocd')"
  type        = string
}

variable "policy_inline_json" {
  description = "Inline IAM policy document as a JSON string"
  type        = string
  default     = null
}

