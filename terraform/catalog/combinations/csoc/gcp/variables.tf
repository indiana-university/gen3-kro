###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
}

variable "csoc_alias" {
  description = "Alias for the csoc (e.g., 'csoc', 'gen3-csoc'). Used as context for IAM policy lookups."
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

###############################################################################
# Network Variables
###############################################################################
variable "enable_vpc" {
  description = "Enable VPC module"
  type        = bool
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "vpc_name" {
  description = "Alias for network_name (provider-agnostic naming)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR (provider-agnostic, not used in GCP auto mode)"
  type        = string
  default     = ""
}

variable "vpc_tags" {
  description = "Additional tags for VPC resources"
  type        = map(string)
  default     = {}
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

variable "availability_zones" {
  description = "List of availability zones for subnets"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = []
}

###############################################################################
# Kubernetes Cluster Variables (Cloud-Agnostic)
###############################################################################
variable "enable_k8s_cluster" {
  description = "Enable Kubernetes cluster module (GKE for GCP)"
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
  default     = {}
}

###############################################################################
# Addon Configurations
###############################################################################
variable "addon_configs" {
  description = "Map of addon configurations from secrets.yaml (includes enable_identity, namespace, service_account, and addon-specific settings)"
  type        = any
}

variable "enable_multi_acct" {
  description = "Enable multi-account setup (computed from spokes)"
  type        = bool
}

###############################################################################
# Spoke Identity Inputs
###############################################################################
variable "spoke_arn_inputs" {
  description = "Map of spoke identities by spoke alias and service (loaded from JSON files or passed directly)"
  type        = map(map(any))
  default     = {}
}

###############################################################################
# ArgoCD Variables
###############################################################################
variable "enable_argocd" {
  description = "Enable ArgoCD deployment module"
  type        = bool
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD workload identity"
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
  description = "Inline IAM policy document for ArgoCD workload identity"
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

