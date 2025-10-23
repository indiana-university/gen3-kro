variable "create" {
  description = "Create terraform resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  type        = string
  default     = "argocd"
}

variable "pod_identities" {
  description = "Map of pod identity outputs from hub/spoke combination"
  type = map(object({
    role_arn      = string
    role_name     = string
    policy_arn    = optional(string)
    service_name  = string
    policy_source = string
  }))
  default = {}
}

variable "addon_configs" {
  description = "Map of addon configurations from config.yaml"
  type        = any
  default     = {}
}

variable "cluster_info" {
  description = "EKS cluster information for ConfigMap"
  type = object({
    cluster_name              = string
    cluster_endpoint          = string
    cluster_version           = string
    account_id                = string
    region                    = string
    oidc_provider             = string
    oidc_provider_arn         = string
    cluster_security_group_id = optional(string)
    vpc_id                    = optional(string)
    private_subnets           = optional(list(string))
    public_subnets            = optional(list(string))
  })
  default = null
}

variable "gitops_context" {
  description = "ArgoCD GitOps metadata for hub and spokes"
  type        = any
  default     = {}
}

variable "spokes" {
  description = "Map of spoke configurations with IAM role ARNs per controller"
  type        = any
  default     = {}
}
