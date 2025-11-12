variable "create" {
  description = "Whether to create the ACK controller ConfigMap"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used in ConfigMap naming)"
  type        = string
}

variable "controller_name" {
  description = "Name of the ACK controller (e.g., 's3', 'rds', 'ec2')"
  type        = string
}

variable "spoke_roles" {
  description = "Map of spoke aliases to their account ID and role ARN for this controller"
  type = map(object({
    account_id = string
    role_arn   = string
  }))
  default = {}
  # Example:
  # {
  #   "spoke1" = {
  #     account_id = "111111111111"
  #     role_arn   = "arn:aws:iam::111111111111:role/spoke1-ack-s3-spoke-role"
  #   }
  #   "spoke2" = {
  #     account_id = "222222222222"
  #     role_arn   = "arn:aws:iam::222222222222:role/spoke2-ack-s3-spoke-role"
  #   }
  # }
}

variable "configmap_namespace" {
  description = "Namespace where ACK controllers look for the role map ConfigMaps"
  type        = string
  default     = "ack-system"
}

variable "labels" {
  description = "Additional labels for the ConfigMap"
  type        = map(string)
  default     = {}
}

