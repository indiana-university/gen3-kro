variable "git_secrets" {
  description = "Git secrets for GitOps Addons"
  type        = any
  default     = {}
}

 variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
  default     = "us-west-2"
}

variable "cluster_info" {
  description = "Information about the EKS cluster"
  type        = any
  default     = {}
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  default     = "argocd"
}

variable "gitops_addons_github_url" {
  description = "The GitHub URL for GitOps Addons"
  default     = "github.com"
}

variable "gitops_fleet_github_url" {
  description = "The GitHub URL for GitOps Fleet"
  default     = "github.com"
}

variable "gitops_workload_github_url" {
  description = "The GitHub URL for GitOps Workload"
  default     = "github.com"
}

variable "gitops_platform_github_url" {
  description = "The GitHub URL for GitOps Platform"
  default     = "github.com"
}

variable "gitops_addons_org_name" {
  description = "The organization name for GitOps Addons"
  default     = "kro"
}

variable "gitops_fleet_org_name" {
  description = "The organization name for GitOps Fleet"
  default     = "kro"
}

variable "gitops_workload_org_name" {
  description = "The organization name for GitOps Workload"
  default     = "kro"
}

variable "gitops_platform_org_name" {
  description = "The organization name for GitOps Platform"
  default     = "kro"
}

variable "gitops_addons_app_id" {
  description = "The GitHub App ID for GitOps Addons"
  default     = "123456"
}

variable "gitops_fleet_app_id" {
  description = "The GitHub App ID for GitOps Fleet"
  default     = "123456"
}

variable "gitops_workload_app_id" {
  description = "The GitHub App ID for GitOps Workload"
  default     = "123456"
}

variable "gitops_platform_app_id" {
  description = "The GitHub App ID for GitOps Platform"
  default     = "123456"
}

variable "gitops_addons_repo_name" {
  description = "The name of the Git repo for GitOps Addons"
  default     = "kro"
}

variable "gitops_fleet_repo_name" {
  description = "The name of the Git repo for GitOps Fleet"
  default     = "kro"
}

variable "gitops_workload_repo_name" {
  description = "The name of the Git repo for GitOps Workload"
  default     = "kro"
}

variable "gitops_platform_repo_name" {
  description = "The name of the Git repo for GitOps Platform"
  default     = "kro"
}

variable "gitops_addons_app_installation_id" {
  description = "The GitHub App Installation ID for GitOps Addons"
  default     = "123456789"
}

variable "gitops_fleet_app_installation_id" {
  description = "The GitHub App Installation ID for GitOps Fleet"
  default     = "123456789"
}

variable "gitops_workload_app_installation_id" {
  description = "The GitHub App Installation ID for GitOps Workload"
  default     = "123456789"
}

variable "gitops_platform_app_installation_id" {
  description = "The GitHub App Installation ID for GitOps Platform"
  default     = "123456789"
}

variable "gitops_addons_app_private_key_ssm_path" {
  description = "The SSM path for the private key of GitOps Addons GitHub App"
  default     = "/path/to/gitops/addons/private/key"
}

variable "gitops_fleet_app_private_key_ssm_path" {
  description = "The SSM path for the private key of GitOps Fleet GitHub App"
  default     = "/path/to/gitops/fleet/private/key"
}

variable "gitops_workload_app_private_key_ssm_path" {
  description = "The SSM path for the private key of GitOps Workload GitHub App"
  default     = "/path/to/gitops/workload/private/key"
}

variable "gitops_platform_app_private_key_ssm_path" {
  description = "The SSM path for the private key of GitOps Platform GitHub App"
  default     = "/path/to/gitops/platform/private/key"
}

variable "outputs_dir" {
  description = "Directory to store generated output files"
  type        = string
  default     = "../../../../../outputs"
}

variable "integrations" {
  description = "Map of integrations with their respective configurations"
  type        = any
  }