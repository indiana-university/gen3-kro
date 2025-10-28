output "vpc_id" {
  description = "The ID of the VPC"
  value       = var.create ? module.vpc[0].vpc_id : null
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = var.create ? module.vpc[0].vpc_cidr_block : null
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = var.create ? module.vpc[0].private_subnets : []
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = var.create ? module.vpc[0].public_subnets : []
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = var.create ? module.vpc[0].private_subnets_cidr_blocks : []
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = var.create ? module.vpc[0].public_subnets_cidr_blocks : []
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = var.create ? module.vpc[0].natgw_ids : []
}

output "azs" {
  description = "List of availability zones used"
  value       = var.create ? module.vpc[0].azs : []
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = var.create ? module.vpc[0].vpc_arn : null
}
