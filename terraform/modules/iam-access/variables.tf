variable "ack_services" {
  type    = list(string)
  default = ["s3", "ec2", "vpc"]
}

variable "hub_account_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "environment" {
  description = "The environment where the cluster is deployed (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_info" {
  description = "Cluster information to be used by the module"
  type        = any
  default     = {}
}

variable "ack_services_config" {
  description = "Configuration for each ACK service including namespace and service account"
  type        = any
  default     = {}
}