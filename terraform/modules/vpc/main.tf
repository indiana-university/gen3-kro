###################################################################################################################################################
# VPC Module
###################################################################################################################################################
module "vpc" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags = merge(
    var.public_subnet_tags,
    {
      "kubernetes.io/role/elb" = 1
    }
  )

  private_subnet_tags = merge(
    var.private_subnet_tags,
    var.cluster_name != "" ? {
      "kubernetes.io/role/internal-elb" = 1
      "karpenter.sh/discovery"          = var.cluster_name
    } : {}
  )

  tags = var.tags
}

###################################################################################################################################################
# Notes
###################################################################################################################################################
# Availability zones are provided via variables; no additional data sources are required.

