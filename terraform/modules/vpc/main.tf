###################################################################################################################################################
# VPC Module
###################################################################################################################################################
module "vpc" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = [for a in data.aws_availability_zones.available[0].names : a if a != "us-east-1e"]
  private_subnets = [for k, v in [for a in data.aws_availability_zones.available[0].names : a if a != "us-east-1e"] : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in [for a in data.aws_availability_zones.available[0].names : a if a != "us-east-1e"] : cidrsubnet(var.vpc_cidr, 8, k + 240)]

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
# Data Sources
###################################################################################################################################################
data "aws_availability_zones" "available" {
  count = var.create ? 1 : 0

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

