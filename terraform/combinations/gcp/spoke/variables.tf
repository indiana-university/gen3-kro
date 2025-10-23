variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "spoke_alias" {
  description = "Spoke alias"
  type        = string
}

variable "provider" {
  description = "Cloud provider"
  type        = string
  default     = "gcp"
}

variable "project_id" {
  description = "GCP project ID for spoke"
  type        = string
}

variable "addon_configs" {
  description = "Addon configurations for this spoke"
  type        = any
  default     = {}
}

variable "hub_service_accounts" {
  description = "Map of hub service account emails"
  type        = map(string)
  default     = {}
}

variable "iam_base_path" {
  description = "Base path for IAM files"
  type        = string
  default     = "iam"
}

variable "iam_repo_root" {
  description = "Repository root"
  type        = string
  default     = ""
}
