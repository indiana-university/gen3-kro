###############################################################################
# IAM Policy Module Variables (Cloud Agnostic)
###############################################################################

variable "service_name" {
  description = "Name of the service (e.g., 's3', 'ebs-csi', 'argocd')"
  type        = string
}

variable "policy_inline_json" {
  description = "Inline IAM policy document as a JSON string (may contain placeholders)"
  type        = string
  default     = null
}

###############################################################################
# Placeholder Replacement Variables
# These values replace placeholders in policy documents
###############################################################################

# AWS
variable "account_id" {
  description = "AWS Account ID to replace <ACCOUNT_ID> placeholder"
  type        = string
  default     = null
}

variable "csoc_account_id" {
  description = "CSOC AWS Account ID to replace <CSOC_ACCOUNT_ID> placeholder"
  type        = string
  default     = null
}

# Azure
variable "subscription_id" {
  description = "Azure Subscription ID to replace <SUBSCRIPTION_ID> placeholder"
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Azure Tenant ID to replace <TENANT_ID> placeholder"
  type        = string
  default     = null
}

# GCP
variable "project_id" {
  description = "GCP Project ID to replace <PROJECT_ID> placeholder"
  type        = string
  default     = null
}

variable "project_number" {
  description = "GCP Project Number to replace <PROJECT_NUMBER> placeholder"
  type        = string
  default     = null
}

variable "policy_source" {
  description = "Source folder where the policy was loaded from (e.g., '_default', 'gen3-kro-dev/csoc', 'gen3-kro-dev/spoke1')"
  type        = string
  default     = "_default"
}
