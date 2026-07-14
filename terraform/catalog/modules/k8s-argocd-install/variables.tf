variable "enabled" {
  description = "Whether Argo CD installation resources are managed"
  type        = bool
  default     = true
}

variable "csoc_account_id" {
  description = "CSOC account ID used as namespace metadata"
  type        = string
}

variable "argocd_namespace" {
  description = "Argo CD namespace"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Argo CD Helm chart version"
  type        = string
}

variable "argocd_chart_repository" {
  description = "Argo CD Helm chart repository"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "argocd_values" {
  description = "Additional Argo CD Helm values"
  type        = any
  default     = {}
}

variable "enable_argocd_self_managed" {
  description = "Whether to install self-managed Argo CD"
  type        = bool
  default     = false
}

variable "enable_argocd_capability" {
  description = "Whether AWS-managed Argo CD requires the namespace"
  type        = bool
  default     = false
}

variable "argocd_bootstrap_enabled" {
  description = "Whether downstream GitOps bootstrap requires the namespace"
  type        = bool
  default     = false
}

variable "argocd_self_managed_role_arn" {
  description = "IAM role ARN annotated onto self-managed Argo CD service accounts"
  type        = string
  default     = ""
}
