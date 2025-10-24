###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

###############################################################################
# VPC Variables
###############################################################################
variable "enable_vpc" {
  description = "Enable VPC module"
  type        = bool
  default     = false
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = false
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
  default     = {}
}

variable "vpc_tags" {
  description = "Additional tags for VPC resources"
  type        = map(string)
  default     = {}
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC to use (when enable_vpc is false)"
  type        = string
  default     = ""
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs to use (when enable_vpc is false)"
  type        = list(string)
  default     = []
}

###############################################################################
# Explicit Subnet Configuration
###############################################################################
variable "availability_zones" {
  description = "List of availability zones for subnets (e.g., ['us-east-1a', 'us-east-1b', 'us-east-1c'])"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (must match length of availability_zones)"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (must match length of availability_zones)"
  type        = list(string)
  default     = []
}

###############################################################################
# EKS Cluster Variables
###############################################################################
variable "enable_eks_cluster" {
  description = "Enable EKS cluster module"
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster creator admin permissions"
  type        = bool
  default     = false
}

variable "cluster_compute_config" {
  description = "Cluster compute configuration"
  type        = any
  default = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}

variable "eks_cluster_tags" {
  description = "Additional tags for EKS cluster resources"
  type        = map(string)
  default     = {}
}

###############################################################################
# Addon Configurations
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations from config.yaml (includes enable_pod_identity, namespace, service_account, and addon-specific settings)"
  type        = any
  default     = {}
  # Example structure:
  # {
  #   "ebs_csi" = {
  #     enable_pod_identity = true
  #     namespace           = "kube-system"
  #     service_account     = "ebs-csi-controller-sa"
  #     kms_arns            = ["arn:aws:kms:..."]
  #   }
  #   "external_secrets" = {
  #     enable_pod_identity       = true
  #     namespace                 = "external-secrets"
  #     service_account           = "external-secrets"
  #     kms_key_arns              = []
  #     secrets_manager_arns      = []
  #     ssm_parameter_arns        = []
  #     create_permission         = true
  #     attach_custom_policy      = false
  #     policy_statements         = []
  #   }
  # }
}

variable "enable_multi_acct" {
  description = "Enable multi-account setup (computed from spokes)"
  type        = bool
  default     = false
}

###############################################################################
# Spoke ARN Inputs
###############################################################################
variable "spoke_arn_inputs" {
  description = "Map of spoke ARNs by spoke alias and service (loaded from JSON files or passed directly)"
  type        = map(map(any))
  default     = {}
  # Example structure:
  # {
  #   "spoke1" = {
  #     "external_secrets" = {
  #       role_arn = "arn:aws:iam::123456789012:role/..."
  #     }
  #   }
  # }
}

###############################################################################
# ArgoCD Variables
###############################################################################
variable "enable_argocd" {
  description = "Enable ArgoCD deployment module"
  type        = bool
  default     = false
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD pod identity"
  type        = string
  default     = "argocd"
}

variable "argocd_config" {
  description = "ArgoCD Helm chart configuration"
  type        = any
  default     = {}
}

variable "argocd_install" {
  description = "Whether to install ArgoCD Helm chart"
  type        = bool
  default     = false
}

variable "argocd_cluster" {
  description = "ArgoCD cluster secret configuration"
  type        = any
  default     = null
}

variable "argocd_apps" {
  description = "ArgoCD app of apps to deploy"
  type        = any
  default     = {}
}

variable "argocd_outputs_dir" {
  description = "Directory to store ArgoCD generated output files"
  type        = string
  default     = "./outputs/argocd"
}

variable "argocd_inline_policy" {
  description = "Inline IAM policy document for ArgoCD pod identity"
  type        = string
  default     = ""
}

###############################################################################
# IAM GitOps Variables
###############################################################################
variable "iam_git_repo_url" {
  description = "Git repository URL for IAM policy files (e.g., git::https://github.com/org/repo.git)"
  type        = string
  default     = ""
}

variable "iam_git_branch" {
  description = "Git branch to use for IAM policy files"
  type        = string
  default     = "main"
}

variable "iam_base_path" {
  description = "Base path within the Git repository for IAM policy files"
  type        = string
  default     = "terraform/combinations/iam"
}

variable "iam_raw_base_url" {
  description = "Raw file base URL for fetching IAM policies via HTTP (e.g., https://raw.githubusercontent.com/org/repo/branch)"
  type        = string
  default     = ""
}

variable "iam_repo_root" {
  description = "Absolute path to the repository root for local IAM policy files"
  type        = string
  default     = ""
}

