###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name of the GKE cluster (hub cluster name)"
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

variable "project_id" {
  description = "GCP project ID for spoke"
  type        = string
}

###############################################################################
# CSOC Service Account Emails (Unified)
###############################################################################
variable "csoc_pod_identity_arns" {
  description = "Map of csoc workload identity service account emails by service name"
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
variable "enable_argocd" {
  description = "Whether ArgoCD is enabled in the CSOC cluster"
  type        = bool
  default     = false
}

variable "enable_vpc" {
  description = "Whether VPC is enabled in the CSOC cluster"
  type        = bool
  default     = true
}

variable "enable_k8s_cluster" {
  description = "Whether Kubernetes cluster is enabled in the CSOC cluster"
  type        = bool
  default     = true
}

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

variable "outputs_dir" {
  description = "Directory to write output files"
  type        = string
  default     = ""
}

variable "csoc_cluster_secret_annotations" {
  description = "Annotations from the CSOC cluster secret to include in spoke gitops-context"
  type        = map(string)
  default     = {}
}


