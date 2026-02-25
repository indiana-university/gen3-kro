variable "enabled" {
  description = "Whether to manage ArgoCD bootstrap Kubernetes resources"
  type        = bool
  default     = true
}

variable "aws_profile" {
  description = "AWS profile used for EKS token auth"
  type        = string
}

variable "region" {
  description = "AWS region for EKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "CSOC EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "CSOC EKS cluster endpoint"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 CSOC EKS cluster CA data"
  type        = string
  sensitive   = true
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD resources exist"
  type        = string
  default     = "argocd"
}

variable "ssm_repo_secret_names" {
  description = "Map of logical repo name to AWS Secrets Manager secret path. Each entry creates an ArgoCD repo secret."
  type        = map(string)
  default     = {}
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

variable "outputs_dir" {
  description = "Directory where output files (argocd password) are written"
  type        = string
  default     = ""
}

variable "stack_dir" {
  description = "Directory where the connect-csoc.sh script is written (same folder as terragrunt.stack.hcl)"
  type        = string
  default     = ""
}
