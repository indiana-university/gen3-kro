################################################################################
# General Configuration
################################################################################

variable "create" {
  description = "Whether to create the spoke infrastructure resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the cluster (used in ConfigMap naming and labels)"
  type        = string
}

variable "default_region" {
  description = "Default AWS region to use if not specified in spoke configuration"
  type        = string
  default     = "us-east-1"
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Additional annotations to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Spoke Configurations
################################################################################

variable "spokes" {
  description = "List of spoke configurations"
  type        = list(any)
  default     = []
}

variable "spoke_identity_mappings" {
  description = "Map of spoke alias to account_id/subscription_id/project_id from iam-config"
  type        = any
  default     = {}
}

variable "deployments_base_path" {
  description = "Base path for spoke deployments in ArgoCD repo"
  type        = string
  default     = "argocd/deployments/gen3-spokes"
}

################################################################################
# ConfigMap Configuration
################################################################################

variable "namespace" {
  description = "Namespace where the spokes charter ConfigMap will be created"
  type        = string
  default     = "argocd"
}

variable "configmap_name" {
  description = "Name of the spokes charter ConfigMap"
  type        = string
  default     = "spokes-charter"
}
