variable "create" {
  description = "Whether to create the ACK pod identity"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "service_name" {
  description = "ACK service name (e.g., 'iam', 'ec2', 'eks')"
  type        = string
}

###################################################################################################################################################
# Policy Inputs (from ack-iam-policy module)
###################################################################################################################################################
variable "source_policy_documents" {
  description = "List of source policy documents (from ACK repo)"
  type        = list(string)
  default     = []
}

variable "override_policy_documents" {
  description = "List of override policy documents (from local files or URLs)"
  type        = list(string)
  default     = []
}

variable "policy_arns" {
  description = "Map of managed policy ARNs to attach"
  type        = map(string)
  default     = {}
}

variable "has_inline_policy" {
  description = "Whether inline policies are available"
  type        = bool
  default     = false
}

###################################################################################################################################################
# Pod Identity Configuration
###################################################################################################################################################
variable "trust_policy_conditions" {
  description = "Additional trust policy conditions"
  type        = list(any)
  default     = []
}

variable "association_defaults" {
  description = "Default values for pod identity associations"
  type        = any
  default     = {}
}

variable "associations" {
  description = "Map of pod identity associations (cluster_name, namespace, service_account)"
  type        = map(any)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
