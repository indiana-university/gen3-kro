variable "vpc_name" {
  description = "VPC name to be used by pipelines for data"
  type        = string
}
variable "hub_aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "kubeconfig_dir" {
  description = "Relative directory (from env root) for kubeconfig"
  type        = string
  default     = "../../outputs/kube"
}

variable "addons" {
  description = "Kubernetes addons"
  type        = any
  default     = {
    enable_metrics_server               = true
    enable_kyverno                      = true
    enable_kyverno_policies             = true
    enable_kyverno_policy_reporter      = true
    enable_argocd                       = true
    enable_cni_metrics_helper           = false
    enable_kube_state_metrics           = true
    enable_cert_manager                 = false
    enable_external_dns                 = false
    enable_external_secrets             = true
    enable_ack_iam                      = true
    enable_ack_eks                      = true
    enable_ack_ec2                      = true
    enable_ack_efs                      = true
    enable_kro                          = true
    enable_kro_eks_rgs                  = true
    enable_multi_acct                   = true
  }
}

// Removed unused variables: manifests, enable_addon_selector, route53_zone_name
# Github Repos Variables

variable "git_org_name" {
  description = "The name of Github organisation"
  default     = "kro-run"
}

variable "gitops_addons_repo_name" {
  description = "The name of git repo"
  default     = "kro"
}

variable "gitops_addons_repo_path" {
  description = "The path of addons bootstraps in the repo"
  default     = ""
}

variable "gitops_addons_repo_base_path" {
  description = "The base path of addons in the repon"
  default     = ""
}

variable "gitops_addons_repo_revision" {
  description = "The name of branch or tag"
  default     = "main"
}
# Fleet
variable "gitops_fleet_repo_name" {
  description = "The name of Git repo"
  default     = "kro"
}

variable "gitops_fleet_repo_path" {
  description = "The path of fleet bootstraps in the repo"
  default     = ""
}

variable "gitops_fleet_repo_base_path" {
  description = "The base path of fleet in the repon"
  default     = ""
}

variable "gitops_fleet_repo_revision" {
  description = "The name of branch or tag"
  default     = "main"
}

# workload
variable "gitops_workload_repo_name" {
  description = "The name of Git repo"
  default     = "kro"
}

variable "gitops_workload_repo_path" {
  description = "The path of workload bootstraps in the repo"
  default     = ""
}

variable "gitops_workload_repo_base_path" {
  description = "The base path of workloads in the repo"
  default     = ""
}

variable "gitops_workload_repo_revision" {
  description = "The name of branch or tag"
  default     = "main"
}

# Platform
variable "gitops_platform_repo_name" {
  description = "The name of Git repo"
  default     = "kro"
}

variable "gitops_platform_repo_path" {
  description = "The path of platform bootstraps in the repo"
  default     = ""
}

variable "gitops_platform_repo_base_path" {
  description = "The base path of platform in the repo"
  default     = ""
}

variable "gitops_platform_repo_revision" {
  description = "The name of branch or tag"
  default     = "main"
}


variable "user_provided_inline_policy_link" {
  description = "Base URL for user-provided inline policies, with service name appended (e.g., https://example.com/policies/)"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "hub-cluster"
}

variable "use_ack" {
  description = "Defining to use ack or terraform for pod identity if this is true then we will use this label to deploy resouces with ack"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Name of the environment for the Hub Cluster"
  type        = string
  default     = "control-plane"
}

variable "hub_aws_region" {
  description = "AWS region for the Hub Cluster"
  type        = string
  default     = "us-east-1"
}

variable "gitops_addons_github_url" {
  description = "The GitHub URL for GitOps Addons"
  default     = "github.com"
}

variable "iam_config_raw_file_base_url" {
  description = "Base URL for raw file access for IAM config (e.g., for charts). Leave empty to use default GitHub raw URL"
  type        = string
  default     = ""
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

variable "gitops_addons_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Addons app private key"
  type        = string
  default     = "/kro/gitops/addons/app-private-key"
}

variable "gitops_fleet_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Fleet app private key"
  type        = string
  default     = "/kro/gitops/fleet/app-private-key"
}

variable "gitops_workload_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Workload app private key"
  type        = string
  default     = "/kro/gitops/workload/app-private-key"
}

variable "gitops_platform_app_private_key_ssm_path" {
  description = "SSM path for the GitOps Platform app private key"
  type        = string
  default     = "/kro/gitops/platform/app-private-key"
}

variable "gitops_addons_app_id" {
  description = "GitOps Addons app ID"
  type        = string
  default     = ""
}

variable "gitops_fleet_app_id" {
  description = "GitOps Fleet app ID"
  type        = string
  default     = ""
}

variable "gitops_workload_app_id" {
  description = "GitOps Workload app ID"
  type        = string
  default     = ""
}

variable "gitops_platform_app_id" {
  description = "GitOps Platform app ID"
  type        = string
  default     = ""
}

variable "gitops_addons_app_installation_id" {
  description = "GitOps Addons app installation ID"
  type        = string
  default     = ""
}

variable "gitops_fleet_app_installation_id" {
  description = "GitOps Fleet app installation ID"
  type        = string
  default     = ""
}

variable "gitops_workload_app_installation_id" {
  description = "GitOps Workload app installation ID"
  type        = string
  default     = ""
}

variable "gitops_platform_app_installation_id" {
  description = "GitOps Platform app installation ID"
  type        = string
  default     = ""
}

variable "ack_services" {
  type        = set(string)
  description = "Set of ACK services to provision roles/policies for"
  default     = ["iam", "ec2", "eks"]
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default     = {}
}

variable "outputs_dir" {
  description = "Directory to store generated output files"
  type        = string
  default     = "../../../outputs"
}

variable "argocd_chart_version" {
  description = "Version of the ArgoCD Helm chart to use"
  type        = string
  default     = "5.46.0"
}

variable "spokes" {
  description = "List of spoke accounts for cross-account resource provisioning. Account IDs are determined at runtime via AWS credentials."
  type = list(object({
    alias   = string
    region  = string
    profile = string
    tags    = map(string)
  }))
  default = []
}

variable "deployment_stage" {
  description = "Deployment stage (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "enable_cross_account_iam" {
  description = "Enable cross-account IAM roles for spokes"
  type        = bool
  default     = false
}

variable "hub_alias" {
  description = "Hub account alias for deterministic unique naming"
  type        = string
  default     = "hub"
}
