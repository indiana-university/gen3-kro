################################################################################
# Variables — unified inputs for both CSOC and ArgoCD bootstrap modules
################################################################################

# ─── Region ───────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region for the CSOC EKS cluster"
  type        = string
  default     = "us-east-1"
}

# ─── AWS CSOC Module Variables ────────────────────────────────────────────────

variable "aws_profile" {
  description = "AWS profile name for the CSOC account"
  type        = string
  default     = "default"
}

variable "spoke_account_ids" {
  description = "Sink — no longer set from config. Derived inline in main.tf from var.spokes[].provider.account_id."
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "csoc-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "environment" {
  description = "Name of the environment for the CSOC cluster"
  type        = string
  default     = "control-plane"
}

# VPC
variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
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
  description = "Additional tags for public subnets"
  type        = map(any)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
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

# EKS
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
  description = "Cluster compute configuration for EKS"
  type        = any
  default = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}

variable "enable_automode" {
  description = "Enable EKS Auto Mode"
  type        = bool
  default     = true
}

variable "enable_efs" {
  description = "Enable EFS file system"
  type        = bool
  default     = false
}

# ArgoCD on CSOC cluster
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

# External Secrets
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

# Addons
variable "addons" {
  description = "Kubernetes addons configuration"
  type        = any
  default = {
    enable_external_secrets = true
    enable_kro_eks_rgs      = true
    enable_multi_acct       = true
  }
}

# Controller management
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

variable "ack_namespace" {
  description = "Shared namespace for ACK controllers"
  type        = string
  default     = "ack"
}

variable "use_ack" {
  description = "Use ACK for pod identity; enables ACK labels on ArgoCD resources"
  type        = bool
  default     = true
}

# GitOps — Addons
variable "git_org_name" {
  description = "GitHub organisation name"
  type        = string
  default     = "kro-run"
}

variable "gitops_addons_repo_name" {
  description = "Addons git repo name"
  type        = string
  default     = "kro"
}

variable "gitops_addons_repo_path" {
  description = "Addons bootstrap path in repo"
  type        = string
  default     = "bootstrap"
}

variable "gitops_addons_repo_base_path" {
  description = "Addons base path in repo"
  type        = string
  default     = "argocd/"
}

variable "gitops_addons_repo_revision" {
  description = "Addons branch or tag"
  type        = string
  default     = "main"
}

variable "gitops_addons_github_url" {
  description = "GitHub Enterprise URL for addons repo"
  type        = string
  default     = "github.com"
}

variable "gitops_addons_org_name" {
  description = "GitHub organisation for addons (overrides git_org_name)"
  type        = string
  default     = ""
}

# GitOps — Fleet
variable "gitops_fleet_repo_name" {
  description = "Fleet git repo name"
  type        = string
  default     = "kro"
}

variable "gitops_fleet_repo_path" {
  description = "Fleet bootstrap path in repo"
  type        = string
  default     = "bootstrap"
}

variable "gitops_fleet_repo_base_path" {
  description = "Fleet base path in repo"
  type        = string
  default     = "argocd/"
}

variable "gitops_fleet_repo_revision" {
  description = "Fleet branch or tag"
  type        = string
  default     = "main"
}

variable "gitops_fleet_github_url" {
  description = "GitHub Enterprise URL for fleet repo"
  type        = string
  default     = "github.com"
}

variable "gitops_fleet_org_name" {
  description = "GitHub organisation for fleet"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}

# ─── ArgoCD Bootstrap Module Variables ────────────────────────────────────────

variable "argocd_bootstrap_enabled" {
  description = "Whether to manage ArgoCD bootstrap Kubernetes resources"
  type        = bool
  default     = true
}

variable "ssm_repo_secret_names" {
  description = "Map of logical repo name to AWS Secrets Manager secret path"
  type        = map(string)
  default     = {}
}

variable "argocd_cluster_secret_name" {
  description = "Kubernetes secret name for the ArgoCD cluster secret"
  type        = string
  default     = ""
}

variable "outputs_dir" {
  description = "Directory where output files (argocd password, scripts) are written"
  type        = string
  default     = ""
}

variable "stack_dir" {
  description = "Directory where connect-csoc.sh is written"
  type        = string
  default     = ""
}

# ─── Shared config sink variables ─────────────────────────────────────────────
# These keys exist in shared.auto.tfvars.json for Terragrunt / scripts but are
# not consumed by Terraform modules. Declaring them here prevents "no variable
# named …" errors when the JSON is auto-loaded.

variable "backend_bucket" {
  description = "(Sink) S3 bucket for Terraform state — consumed by install.sh, not modules"
  type        = string
  default     = ""
}

variable "backend_key" {
  description = "(Sink) S3 state key — consumed by install.sh, not modules"
  type        = string
  default     = ""
}

variable "backend_region" {
  description = "(Sink) S3 state region — consumed by install.sh, not modules"
  type        = string
  default     = ""
}

variable "csoc_account_id" {
  description = "(Sink) CSOC AWS account ID — consumed by Terragrunt, not Terraform modules"
  type        = string
  default     = ""
}

variable "spokes" {
  description = "(Sink) Spoke definitions — consumed by Terragrunt IAM setup, not Terraform modules"
  type        = any
  default     = []
}

variable "developer_identity" {
  description = "(Sink) Developer identity config — consumed by Terragrunt, not Terraform modules"
  type        = any
  default     = {}
}

variable "iam_base_path" {
  description = "(Sink) IAM policy files base path — consumed by Terragrunt, not Terraform modules"
  type        = string
  default     = "iam"
}

variable "_doc" {
  description = "(Sink) Documentation field in JSON — ignored"
  type        = string
  default     = ""
}
