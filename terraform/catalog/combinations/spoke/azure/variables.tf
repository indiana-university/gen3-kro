###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name of the AKS cluster (hub cluster name)"
  type        = string
}

variable "spoke_alias" {
  description = "Alias/name for this spoke account (e.g., 'spoke1', 'spoke2')"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider for this spoke: 'aws', 'azure', or 'gcp'"
  type        = string
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Provider must be one of: aws, azure, gcp"
  }
}

variable "subscription_id" {
  description = "Azure subscription ID for spoke"
  type        = string
}

###############################################################################
# CSOC Identity Principal IDs (Unified)
###############################################################################
variable "csoc_pod_identity_arns" {
  description = "Map of csoc workload identity principal IDs by service name"
  type        = map(string)
}

###############################################################################
# Addon Configuration Variables
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations for this spoke from secrets.yaml (includes enable_identity per addon)"
  type        = map(any)
}

variable "csoc_addon_configs" {
  description = "Map of addon configurations from csoc (used as reference for services)"
  type        = any
}

###############################################################################
# IAM Policy Variables
###############################################################################
variable "spoke_iam_policies" {
  description = "Map of IAM policies for spoke services (service_name => policy_json_string)"
  type        = map(string)
  default     = {}
}

###############################################################################
# ArgoCD and Cluster Information Variables
###############################################################################
variable "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  type        = string
}

variable "region" {
  description = "Region for this spoke (cloud-agnostic)"
  type        = string
  default     = ""
}

variable "cluster_info" {
  description = "Cluster information for ConfigMap generation"
  type = object({
    cluster_name              = string
    cluster_endpoint          = string
    cluster_version           = string
    region                    = string
    account_id                = string
    oidc_provider             = string
    oidc_provider_arn         = optional(string)
    cluster_security_group_id = optional(string)
    vpc_id                    = optional(string)
    private_subnets           = optional(list(string))
    public_subnets            = optional(list(string))
  })
}


