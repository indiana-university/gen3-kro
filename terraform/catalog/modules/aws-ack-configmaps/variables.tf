variable "create" {
  description = "Whether to create the ACK controller ConfigMaps"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used in ConfigMap naming)"
  type        = string
}

variable "controller_spoke_roles" {
  description = "Map of controller names to spoke roles mapping"
  type = map(map(object({
    account_id = string
    role_arn   = string
  })))
  default = {}
  # Example:
  # {
  #   "ack-s3" = {
  #     "spoke1" = {
  #       account_id = "111111111111"
  #       role_arn   = "arn:aws:iam::111111111111:role/spoke1-ack-s3-spoke-role"
  #     }
  #     "spoke2" = {
  #       account_id = "222222222222"
  #       role_arn   = "arn:aws:iam::222222222222:role/spoke2-ack-s3-spoke-role"
  #     }
  #   }
  #   "ack-rds" = {
  #     "spoke1" = {
  #       account_id = "111111111111"
  #       role_arn   = "arn:aws:iam::111111111111:role/spoke1-ack-rds-spoke-role"
  #     }
  #   }
  # }
}
