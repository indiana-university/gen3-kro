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
# GitOps Variables - Simplified with separate repository URLs

variable "gitops_org_name" {
  description = "GitHub organization name"
  type        = string
  default     = "kro-run"
}

variable "gitops_repo_name" {
  description = "GitOps repository name"
  type        = string
  default     = "kro"
}

variable "gitops_hub_repo_url" {
  description = "Repository URL for hub/bootstrap manifests"
  type        = string
  default     = ""
}

variable "gitops_rgds_repo_url" {
  description = "Repository URL for RGDs and application-sets"
  type        = string
  default     = ""
}

variable "gitops_spokes_repo_url" {
  description = "Repository URL for spoke configurations"
  type        = string
  default     = ""
}

variable "gitops_branch" {
  description = "Git branch for all ArgoCD applications"
  type        = string
  default     = "main"
}

variable "gitops_bootstrap_path" {
  description = "Path to bootstrap ApplicationSets in the repo"
  type        = string
  default     = "argocd/bootstrap"
}

variable "gitops_rgds_path" {
  description = "Path to RGDs (shared graphs) in the repo"
  type        = string
  default     = "argocd/shared"
}

variable "gitops_spokes_path" {
  description = "Path to spoke configurations in the repo"
  type        = string
  default     = "argocd/spokes"
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

variable "enable_argo" {
  description = "Enable ArgoCD bootstrap"
  type        = bool
  default     = true
}

variable "hub_aws_region" {
  description = "AWS region for the Hub Cluster"
  type        = string
  default     = "us-east-1"
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
