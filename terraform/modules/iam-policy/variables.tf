###################################################################################################################################################
# Generic IAM Policy Module
# Loads IAM policies from Git or local filesystem for any service type (ACK, addon, ArgoCD, custom)
###################################################################################################################################################

variable "service_type" {
  description = "Type of service: 'acks', 'addons'"
  type        = string
  validation {
    condition     = contains(["acks", "addons"], var.service_type)
    error_message = "service_type must be one of: acks, addons"
  }
}

variable "service_name" {
  description = "Name of the service (e.g., 's3', 'ebs-csi', 'argocd')"
  type        = string
}

variable "context" {
  description = "Deployment context: 'hub' or spoke alias"
  type        = string
  default     = "hub"
}

variable "iam_policy_repo_url" {
  description = "Git repository URL for IAM policy files (e.g., git::https://github.com/org/repo.git)"
  type        = string
  default     = ""
}

variable "iam_policy_branch" {
  description = "Git branch to use for IAM policy files"
  type        = string
  default     = "main"
}

variable "iam_policy_base_path" {
  description = "Base path within the Git repository for IAM policy files (e.g., 'iam' or 'terraform/combinations/iam')"
  type        = string
  default     = "iam"
}

variable "repo_root_path" {
  description = "Path to the repository root for locating IAM policy files (used when not using Git URLs)"
  type        = string
  default     = ""
}

variable "custom_inline_policy" {
  description = "Custom inline policy document to use instead of loading from filesystem"
  type        = string
  default     = null
}

variable "custom_managed_arns" {
  description = "Custom managed policy ARNs to use instead of loading from filesystem"
  type        = map(string)
  default     = {}
}

variable "custom_override_policy" {
  description = "Custom override policy document"
  type        = string
  default     = null
}
