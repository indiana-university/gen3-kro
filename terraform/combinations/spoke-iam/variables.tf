###############################################################################
# Global Variables
###############################################################################
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_name" {
  description = "Name of the EKS cluster (hub cluster name) the ACK roles target"
  type        = string
}

variable "spoke_alias" {
  description = "Alias/name for this spoke account (e.g., 'spoke1', 'spoke2')"
  type        = string
}

###############################################################################
# ACK Configuration Variables
###############################################################################
variable "ack_configs" {
  description = "Map of ACK controller configurations for this spoke from config.yaml (includes enable_pod_identity per controller)"
  type        = map(any)
  default     = {}
  # Example structure:
  # {
  #   "iam" = {
  #     enable_pod_identity = true
  #   }
  #   "s3" = {
  #     enable_pod_identity = false  # Disabled for this spoke
  #   }
  # }
}

variable "hub_ack_configs" {
  description = "Map of ACK controller configurations from hub (used as reference for services)"
  type        = map(any)
  default     = {}
}
