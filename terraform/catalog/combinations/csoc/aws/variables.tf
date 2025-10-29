###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "csoc_alias" {
  description = "Alias for the csoc (e.g., 'csoc', 'gen3-csoc'). Used as context for IAM policy lookups."
  type        = string
}

###############################################################################
# VPC Variables
###############################################################################
variable "enable_vpc" {
  description = "Enable VPC module"
  type        = bool
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
}

variable "vpc_tags" {
  description = "Additional tags for VPC resources"
  type        = map(string)
}

variable "existing_vpc_id" {
  description = "ID of an existing VPC to use (when enable_vpc is false)"
  type        = string
}

variable "existing_subnet_ids" {
  description = "List of existing subnet IDs to use (when enable_vpc is false)"
  type        = list(string)
}

###############################################################################
# Explicit Subnet Configuration
###############################################################################
variable "availability_zones" {
  description = "List of availability zones for subnets (e.g., ['us-east-1a', 'us-east-1b', 'us-east-1c'])"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (must match length of availability_zones)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (must match length of availability_zones)"
  type        = list(string)
}

###############################################################################
# Kubernetes Cluster Variables (Cloud-Agnostic)
###############################################################################
variable "enable_k8s_cluster" {
  description = "Enable Kubernetes cluster module (EKS for AWS, AKS for Azure, GKE for GCP)"
  type        = bool
}

variable "cluster_version" {
  description = "Kubernetes version for the cluster"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster creator admin permissions"
  type        = bool
}

variable "cluster_compute_config" {
  description = "Cluster compute configuration"
  type        = any
}

variable "k8s_cluster_tags" {
  description = "Additional tags for Kubernetes cluster resources"
  type        = map(string)
}

###############################################################################
# Addon Configurations
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations from secrets.yaml (includes enable_identity, namespace, service_account, and addon-specific settings)"
  type        = any
  # Example structure:
  # {
  #   "ebs_csi" = {
  #     enable_identity = true
  #     namespace           = "kube-system"
  #     service_account     = "ebs-csi-controller-sa"
  #     kms_arns            = ["arn:aws:kms:..."]
  #   }
  #   "external_secrets" = {
  #     enable_identity       = true
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
}

###############################################################################
# Spoke ARN Inputs
###############################################################################
variable "spoke_arn_inputs" {
  description = "Map of spoke ARNs by spoke alias and service (loaded from JSON files or passed directly)"
  type        = map(map(any))
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
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD pod identity"
  type        = string
}

variable "argocd_config" {
  description = "ArgoCD Helm chart configuration"
  type        = any
}

variable "argocd_install" {
  description = "Whether to install ArgoCD Helm chart"
  type        = bool
}

variable "argocd_cluster" {
  description = "ArgoCD cluster secret configuration"
  type        = any
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
  default     = null
}

###############################################################################
# IAM Policy Variables
###############################################################################
variable "csoc_iam_policies" {
  description = "Map of IAM policies for csoc services (service_name => policy_json_string)"
  type        = map(string)
  default     = {}
}

###############################################################################
# End of File
###############################################################################
