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
  default     = "azure"
}

variable "subscription_id" {
  description = "Azure subscription ID for spoke"
  type        = string
}

variable "addon_configs" {
  description = "Addon configurations for this spoke"
  type        = any
  default     = {}
}

variable "hub_managed_identities" {
  description = "Map of hub managed identity principal IDs"
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
