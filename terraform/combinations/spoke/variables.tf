###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster (hub cluster name) the ACK roles target"
  type        = string
}

variable "spoke_alias" {
  description = "Alias/name for this spoke account (e.g., 'spoke1', 'spoke2')"
  type        = string
}

###############################################################################
# ACK Configuration Variables
###############################################################################
variable "ack_configs" {
  description = "Map of ACK controller configurations for this spoke from config.yaml (includes enable_pod_identity per controller)"
  type        = map(any)
  default     = {}
  # Example structure:
  # {
  #   "iam" = {
  #     enable_pod_identity = true
  #   }
  #   "s3" = {
  #     enable_pod_identity = false  # Disabled for this spoke
  #   }
  # }
}

variable "hub_ack_configs" {
  description = "Map of ACK controller configurations from hub (used as reference for services)"
  type        = map(any)
  default     = {}
}

variable "hub_pod_identity_arns" {
  description = "Map of hub ACK pod identity role ARNs by controller name (passed from hub's ACK module outputs)"
  type        = map(string)
  default     = {}
  # Example structure:
  # {
  #   "iam" = "arn:aws:iam::123456789012:role/gen3-kro-hub-ack-iam-pod-identity"
  #   "s3"  = "arn:aws:iam::123456789012:role/gen3-kro-hub-ack-s3-pod-identity"
  # }
}

###############################################################################
# Addon Configuration Variables
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations for this spoke from config.yaml (includes enable_pod_identity per addon)"
  type        = map(any)
  default     = {}
  # Example structure:
  # {
  #   "argocd" = {
  #     enable_pod_identity = true
  #   }
  #   "external_secrets" = {
  #     enable_pod_identity = false  # Disabled for this spoke
  #   }
  # }
}

variable "hub_addon_configs" {
  description = "Map of addon configurations from hub (used as reference for services)"
  type        = any
  default     = {}
}

variable "hub_addon_pod_identity_arns" {
  description = "Map of hub addon pod identity role ARNs by addon name (passed from hub's addon module outputs)"
  type        = map(string)
  default     = {}
  # Example structure:
  # {
  #   "argocd" = "arn:aws:iam::123456789012:role/gen3-kro-hub-argocd-pod-identity"
  #   "external_secrets"  = "arn:aws:iam::123456789012:role/gen3-kro-hub-external-secrets-pod-identity"
  # }
}

###############################################################################
# IAM Git Configuration Variables
###############################################################################
variable "iam_git_repo_url" {
  description = "Git repository URL for IAM policy files"
  type        = string
  default     = ""
}

variable "iam_git_branch" {
  description = "Git branch for IAM policy files"
  type        = string
  default     = "main"
}

variable "iam_base_path" {
  description = "Base path for IAM policies in the repository"
  type        = string
  default     = "iam"
}

variable "iam_raw_base_url" {
  description = "Raw file base URL for fetching IAM policies via HTTP"
  type        = string
  default     = ""
}

variable "iam_repo_root" {
  description = "Path to the repository root for locating IAM policy files"
  type        = string
  default     = ""
}

###############################################################################
# ArgoCD and Cluster Information Variables
###############################################################################
variable "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  type        = string
  default     = "argocd"
}

variable "region" {
  description = "AWS region for this spoke"
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
    oidc_provider_arn         = string
    cluster_security_group_id = optional(string)
    vpc_id                    = optional(string)
    private_subnets           = optional(list(string))
    public_subnets            = optional(list(string))
  })
  default = null
}

