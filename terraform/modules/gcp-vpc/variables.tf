###############################################################################
# GCP VPC Module
# Creates VPC network and subnets for GKE
###############################################################################

variable "create" {
  description = "Whether to create the VPC"
  type        = bool
  default     = true
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnets" {
  description = "List of subnets to create"
  type = list(object({
    subnet_name           = string
    subnet_ip             = string
    subnet_region         = string
    subnet_private_access = bool
  }))
  default = []
}

variable "routing_mode" {
  description = "Network routing mode (REGIONAL or GLOBAL)"
  type        = string
  default     = "REGIONAL"
}
