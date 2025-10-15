variable "create" {
  description = "Whether to fetch and process ACK IAM policies"
  type        = bool
  default     = true
}

variable "service_name" {
  description = "ACK service name (e.g., 'iam', 'ec2', 'eks')"
  type        = string
}

variable "override_policy_path" {
  description = "Path to local JSON file with override IAM policy (e.g., '/iam/pod-identities/iam.json')"
  type        = string
  default     = ""
}

variable "override_policy_url" {
  description = "URL to fetch override IAM policy from (alternative to override_policy_path)"
  type        = string
  default     = ""
}

variable "additional_policy_arns" {
  description = "Additional managed policy ARNs to attach"
  type        = map(string)
  default     = {}
}
