variable "create" {
  description = "Whether to create VPC resources"
  type        = bool
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for tagging subnets)"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
}

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
}

###################################################################################################################################################
# Explicit Subnet Configuration
###################################################################################################################################################
variable "availability_zones" {
  description = "List of availability zones for subnets (e.g., ['us-east-1a', 'us-east-1b', 'us-east-1c'])"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (must match length of availability_zones)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (must match length of availability_zones)"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all VPC resources"
  type        = map(string)
}

