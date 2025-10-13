variable "ack_services" {
  type    = list(string)
}

variable "tags" {
  type    = map(string)
}

variable "alias_tag" {
  description = "Alias tag to identify the spoke account for unique resource naming"
  type        = string
}

variable "spoke_alias" {
  description = "Spoke account alias for deterministic unique naming"
  type        = string
}

variable "enable_external_spoke" {
  description = "Whether this is an external spoke (different account from hub)"
  type        = bool
  default     = false
}

variable "enable_internal_spoke" {
  description = "Whether this is an internal spoke (same account as hub)"
  type        = bool
  default     = true
}

variable "deployment_stage" {
  description = "The deployment stage where the cluster is deployed (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_info" {
  description = "Cluster information to be used by the module"
  type        = any
}

variable "ack_hub_roles" {
  description = "Map of ACK Hub Role resources by service"
  type        = any
  default     = {}
}

