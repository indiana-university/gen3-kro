variable "enabled" {
  description = "Whether to manage in-cluster bootstrap resources"
  type        = bool
  default     = true
}

variable "aws_profile" {
  description = "AWS profile used for EKS token auth"
  type        = string
}

variable "region" {
  description = "AWS region for the existing EKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "Existing CSOC EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "Existing CSOC EKS cluster endpoint"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 CSOC EKS cluster CA data"
  type        = string
  sensitive   = true
}

variable "foundation_dependency_token" {
  description = "Opaque foundation dependency token used to order bootstrap after AWS foundation readiness"
  type        = string
  default     = ""
}

variable "csoc_account_id" {
  description = "CSOC AWS account ID used for in-cluster metadata annotations"
  type        = string
  default     = ""
}

variable "argocd_namespace" {
  description = "Namespace where Argo CD resources are managed"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "argocd_chart_repository" {
  description = "Argo CD Helm chart repository"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "argocd_values" {
  description = "Custom values for the Argo CD Helm chart"
  type        = any
  default     = {}
}

variable "enable_argocd_self_managed" {
  description = "Whether Terraform should install self-managed Argo CD with Helm"
  type        = bool
  default     = false
}

variable "enable_argocd_capability" {
  description = "Whether AWS-managed Argo CD capability is enabled in the foundation"
  type        = bool
  default     = false
}

variable "argocd_self_managed_role_arn" {
  description = "IAM role ARN annotated on self-managed Argo CD service accounts"
  type        = string
  default     = ""
}

variable "argocd_bootstrap_enabled" {
  description = "Whether to manage Argo CD bootstrap secrets and ApplicationSet"
  type        = bool
  default     = true
}

variable "ssm_repo_secret_names" {
  description = "Map of logical repo name to AWS Secrets Manager secret path"
  type        = map(string)
  default     = {}
}

variable "argocd_cluster_secret_name" {
  description = "Kubernetes secret name for the Argo CD cluster secret"
  type        = string
  default     = ""
}

variable "argocd_cluster_labels" {
  description = "Additional labels for the Argo CD cluster secret"
  type        = map(any)
  default     = {}
}

variable "argocd_cluster_annotations" {
  description = "Base annotations for the Argo CD cluster secret"
  type        = map(any)
  default     = {}
}

variable "ack_self_managed_role_arn" {
  description = "CSOC shared ACK role ARN exposed to Argo CD add-ons"
  type        = string
  default     = ""
}

variable "spoke_account_ids" {
  description = "Map of spoke alias to AWS account ID"
  type        = map(string)
  default     = {}
}

variable "outputs_dir" {
  description = "Directory where output files are written"
  type        = string
  default     = ""
}

variable "stack_dir" {
  description = "Directory where the connect-csoc.sh script is written"
  type        = string
  default     = ""
}
