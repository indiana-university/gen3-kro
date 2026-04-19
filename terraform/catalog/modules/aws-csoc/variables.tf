# AWS Profile Configuration
variable "aws_profile" {
  description = "AWS profile name for CSOC cluster"
  type        = string
  default     = "default"
}

variable "spoke_account_ids" {
  description = "Map of spoke alias to AWS account ID (resolved from spoke profiles at plan time)"
  type        = map(string)
  default     = {}
}

variable "spoke_dns_config" {
  description = "Map of spoke alias to DNS config (hosted_zone_id, hosted_zone_name)"
  type = map(object({
    hosted_zone_id   = string
    hosted_zone_name = string
  }))
  default = {}
}

variable "csoc_alias" {
  description = "Base alias for all CSOC resources. Derived names: cluster={csoc_alias}-csoc-cluster, vpc={csoc_alias}-csoc-vpc, roles={csoc_alias}-csoc-role, etc."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use for subnets"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Explicit private subnet CIDRs (optional)"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Explicit public subnet CIDRs (optional)"
  type        = list(string)
  default     = []
}

variable "public_subnet_tags" {
  description = "Additional tags to apply to public subnets"
  type        = map(any)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags to apply to private subnets"
  type        = map(any)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateways for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable cluster creator admin permissions"
  type        = bool
  default     = true
}

variable "cluster_compute_config" {
  description = "Cluster compute configuration for EKS module"
  type        = any
  default = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD resources"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "argocd_chart_repository" {
  description = "ArgoCD Helm chart repository"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "argocd_values" {
  description = "Custom values for ArgoCD Helm chart"
  type        = any
  default     = {}
}

variable "external_secrets_namespace" {
  description = "Namespace for external-secrets"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "Service account name for external-secrets"
  type        = string
  default     = "external-secrets-sa"
}

variable "addons" {
  description = "Kubernetes addons"
  type        = any
  default = {
    enable_external_secrets = true
    enable_kro_csoc_rgs     = true
    enable_multi_acct       = true
  }
}

###############################################################################
# Controller Management Types and Enablement
###############################################################################

variable "ack_management_type" {
  description = "ACK deployment type: 'aws_managed' or 'self_managed'"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.ack_management_type)
    error_message = "ack_management_type must be 'aws_managed' or 'self_managed'"
  }
}

variable "kro_management_type" {
  description = "KRO deployment type: 'aws_managed' or 'self_managed'"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.kro_management_type)
    error_message = "kro_management_type must be 'aws_managed' or 'self_managed'"
  }
}

variable "argocd_management_type" {
  description = "ArgoCD deployment type: 'aws_managed' or 'self_managed'"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.argocd_management_type)
    error_message = "argocd_management_type must be 'aws_managed' or 'self_managed'"
  }
}

variable "enable_ack_capability" {
  description = "Enable AWS-managed ACK EKS capability"
  type        = bool
  default     = false
}

variable "enable_kro_capability" {
  description = "Enable AWS-managed KRO EKS capability"
  type        = bool
  default     = false
}

variable "enable_argocd_capability" {
  description = "Enable AWS-managed ArgoCD EKS capability"
  type        = bool
  default     = false
}

variable "enable_ack_self_managed" {
  description = "Enable shared ACK CSOC role for self-managed controllers"
  type        = bool
  default     = false
}

variable "enable_argocd_self_managed" {
  description = "Enable self-managed ArgoCD via Helm"
  type        = bool
  default     = false
}

variable "argocd_bootstrap_enabled" {
  description = "Whether ArgoCD bootstrap resources (secrets, ApplicationSet) are managed — triggers namespace creation"
  type        = bool
  default     = false
}

variable "ack_namespace" {
  description = "Shared namespace for ACK controllers (used for CSOC role trust)"
  type        = string
  default     = "ack"
}

# Github Repos Variables

variable "git_org_name" {
  description = "The name of Github organisation"
  type        = string
  default     = "kro-run"
}

variable "gitops_addons_repo_name" {
  description = "The name of git repo"
  type        = string
  default     = "kro"
}

variable "gitops_addons_repo_path" {
  description = "The path of addons bootstraps in the repo"
  type        = string
  default     = "bootstrap"
}

variable "gitops_addons_repo_base_path" {
  description = "The base path of addons in the repo"
  type        = string
  default     = "argocd/"
}

variable "gitops_addons_repo_revision" {
  description = "The name of branch or tag"
  type        = string
  default     = "main"
}
# Fleet
variable "gitops_fleet_repo_name" {
  description = "The name of Git repo"
  type        = string
  default     = "kro"
}

variable "gitops_fleet_repo_path" {
  description = "The path of fleet bootstraps in the repo"
  type        = string
  default     = "bootstrap"
}

variable "gitops_fleet_repo_base_path" {
  description = "The base path of fleet in the repo"
  type        = string
  default     = "argocd/"
}

variable "gitops_fleet_repo_revision" {
  description = "The name of branch or tag"
  type        = string
  default     = "main"
}

# GitOps Addons - Additional Configuration
variable "gitops_addons_github_url" {
  description = "GitHub Enterprise URL for addons repo"
  type        = string
  default     = "github.com"
}

variable "gitops_addons_org_name" {
  description = "GitHub organisation name for addons repo (alternative to git_org_name)"
  type        = string
  default     = ""
}

# GitOps Fleet - Additional Configuration
variable "gitops_fleet_github_url" {
  description = "GitHub Enterprise URL for fleet repo"
  type        = string
  default     = "github.com"
}

variable "gitops_fleet_org_name" {
  description = "GitHub organisation name for fleet repo"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_efs" {
  description = "Enabling EFS file system"
  type        = bool
  default     = false
}

variable "enable_automode" {
  description = "Enabling Automode Cluster"
  type        = bool
  default     = true
}

variable "use_ack" {
  description = "Defining to use ack or terraform for pod identity if this is true then we will use this label to deploy resources with ack"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Name of the environment for the CSOC cluster"
  type        = string
  default     = "control-plane"
}
