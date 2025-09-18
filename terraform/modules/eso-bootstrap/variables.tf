variable "namespace" {
  description = "Namespace to install external-secrets into"
  type        = string
  default     = "external-secrets"
}

variable "service_account" {
  description = "Service account name for External Secrets Operator"
  type        = string
  default     = "external-secrets-sa"
}

variable "chart_version" {
  description = "Helm chart version for ESO"
  type        = string
  default     = "0.10.3"
}

variable "aws_region" {
  description = "AWS region where SSM/SecretsManager is located"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name (used in SSM path)"
  type        = string
}

variable "repos" {
  description = <<EOT
Map of repos that need credentials.
Key = repo name (used for secret name).
Value = object with:
  - url (string): Git repo URL
  - app_id (string): GitHub App ID
  - installation_id (string): GitHub App Installation ID
  - ssm_path (string): SSM parameter path where private key is stored
EOT
  type = any
  default = {}
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed (for repo secrets)"
  type        = string
  default     = "argocd"
}
