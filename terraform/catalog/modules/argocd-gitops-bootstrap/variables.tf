variable "enabled" {
  description = "Whether to manage ArgoCD bootstrap Kubernetes resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "CSOC EKS cluster name"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD resources exist"
  type        = string
  default     = "argocd"
}

variable "ssm_repo_secret_names" {
  description = "Optional private repo credential config. Supports legacy map form or { repos = [{ name, ssm_secret_name }] }; { repos = [] } means no private repo credentials."
  type        = any
  default = {
    repos = []
  }
}

variable "argocd_cluster_secret_name" {
  description = "Kubernetes secret name used as ArgoCD cluster secret"
  type        = string
  default     = ""
}

variable "argocd_cluster_labels" {
  description = "Additional labels for ArgoCD cluster secret"
  type        = map(any)
  default     = {}
}

variable "argocd_cluster_annotations" {
  description = "Base annotations for ArgoCD cluster secret"
  type        = map(any)
  default     = {}
}

variable "ack_self_managed_role_arn" {
  description = "CSOC shared ACK role ARN exposed to ArgoCD add-ons"
  type        = string
  default     = ""
}

variable "spoke_account_ids" {
  description = "Map of spoke alias to AWS account ID"
  type        = map(string)
  default     = {}
}

variable "bootstrap_dependency_token" {
  description = "Opaque dependency token used by wrapper modules to order Argo CD install before bootstrap resources"
  type        = string
  default     = ""
}
