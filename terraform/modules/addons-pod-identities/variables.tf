variable "create" {
  description = "Whether to create pod identity resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "addon_configs" {
  description = "Map of addon configurations from config.yaml (includes enable_pod_identity, namespace, service_account, and addon-specific settings)"
  type        = map(any)
  default     = {}
  # Example structure:
  # {
  #   "ebs_csi" = {
  #     enable_pod_identity = true
  #     namespace           = "kube-system"
  #     service_account     = "ebs-csi-controller-sa"
  #     kms_arns            = ["arn:aws:kms:..."]
  #   }
  #   "external_secrets" = {
  #     enable_pod_identity       = true
  #     namespace                 = "external-secrets"
  #     service_account           = "external-secrets"
  #     kms_key_arns              = []
  #     secrets_manager_arns      = []
  #     ssm_parameter_arns        = []
  #     create_permission         = true
  #     attach_custom_policy      = false
  #     policy_statements         = []
  #   }
  # }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
