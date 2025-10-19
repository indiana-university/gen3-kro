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

variable "hub_pod_identity_arns" {
  description = "Map of hub ACK pod identity role ARNs by controller name (passed from hub's ACK module outputs)"
  type        = map(string)
  default     = {}
  # Example structure:
  # {
  #   "iam" = "arn:aws:iam::123456789012:role/gen3-kro-hub-ack-iam-pod-identity"
  #   "s3"  = "arn:aws:iam::123456789012:role/gen3-kro-hub-ack-s3-pod-identity"
  # }
}
