###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster the ACK roles target"
  type        = string
}

###############################################################################
# ACK IAM Policy Variables
###############################################################################
variable "enable_ack" {
  description = "Enable ACK IAM policy module"
  type        = bool
  default     = false
}

variable "ack_services" {
  description = "Map of ACK services to configure"
  type        = map(any)
  default     = {}
}

variable "ack_tags" {
  description = "Additional tags for ACK IAM policy resources"
  type        = map(string)
  default     = {}
}

###############################################################################
# ACK Spoke Role Variables
###############################################################################
variable "enable_ack_spoke_roles" {
  description = "Enable ACK spoke role module"
  type        = bool
  default     = false
}

variable "ack_spoke_accounts" {
  description = "Map of spoke accounts for ACK cross-account access"
  type        = map(any)
  default     = {}
}

variable "ack_spoke_tags" {
  description = "Additional tags for ACK spoke role resources"
  type        = map(string)
  default     = {}
}

variable "ack_hub_pod_identity_role_arns" {
  description = "Map of ACK service names to hub pod identity role ARNs"
  type        = map(string)
  default     = {}
}
