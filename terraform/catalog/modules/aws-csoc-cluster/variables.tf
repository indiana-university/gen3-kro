variable "csoc_alias" {
  description = "Base alias used to name CSOC cluster resources"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use for subnets"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Explicit private subnet CIDRs"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Explicit public subnet CIDRs"
  type        = list(string)
  default     = []
}

variable "public_subnet_tags" {
  description = "Additional public subnet tags"
  type        = map(any)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional private subnet tags"
  type        = map(any)
  default     = {}
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Whether to use one shared NAT gateway"
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is public"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Whether the cluster creator receives administrator access"
  type        = bool
  default     = true
}

variable "cluster_compute_config" {
  description = "EKS Auto Mode compute configuration"
  type        = any
  default = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }
}

variable "environment" {
  description = "CSOC environment name"
  type        = string
  default     = "control-plane"
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
