variable "csoc_alias" {
  description = "Base alias used to name CSOC controller resources"
  type        = string
}

variable "cluster_name" {
  description = "Existing CSOC EKS cluster name"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the CSOC EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN of the CSOC EKS cluster"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace used by self-managed Argo CD"
  type        = string
  default     = "argocd"
}

variable "ack_namespace" {
  description = "Namespace used by self-managed ACK controllers"
  type        = string
  default     = "ack"
}

variable "external_secrets_namespace" {
  description = "External Secrets namespace"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "External Secrets service account"
  type        = string
  default     = "external-secrets-sa"
}

variable "addons" {
  description = "Controller add-on enablement flags"
  type        = any
  default     = {}
}

variable "ack_management_type" {
  description = "ACK deployment type"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.ack_management_type)
    error_message = "ack_management_type must be aws_managed or self_managed"
  }
}

variable "kro_management_type" {
  description = "KRO deployment type"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.kro_management_type)
    error_message = "kro_management_type must be aws_managed or self_managed"
  }
}

variable "argocd_management_type" {
  description = "Argo CD deployment type"
  type        = string
  default     = "self_managed"
  validation {
    condition     = contains(["aws_managed", "self_managed"], var.argocd_management_type)
    error_message = "argocd_management_type must be aws_managed or self_managed"
  }
}

variable "enable_ack_capability" {
  type    = bool
  default = false
}

variable "enable_kro_capability" {
  type    = bool
  default = false
}

variable "enable_argocd_capability" {
  type    = bool
  default = false
}

variable "enable_ack_self_managed" {
  type    = bool
  default = false
}

variable "enable_argocd_self_managed" {
  type    = bool
  default = false
}

variable "environment" {
  description = "CSOC environment name"
  type        = string
  default     = "control-plane"
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
