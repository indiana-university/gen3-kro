module "eks" {
  #checkov:skip=CKV_TF_1:We are using version control for those modules
  #checkov:skip=CKV_TF_2:We are using version control for those modules
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name                   = local.cluster_name
  kubernetes_version     = local.cluster_version
  endpoint_public_access = var.cluster_endpoint_public_access

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  compute_config = var.cluster_compute_config

  # Disable all EKS control plane logging to CloudWatch (default enables all 5 types)
  enabled_log_types = []

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = local.vpc_name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  public_subnet_tags = merge(
    {
      "kubernetes.io/role/elb" = 1
    },
    var.public_subnet_tags
  )

  private_subnet_tags = merge(
    {
      "kubernetes.io/role/internal-elb" = 1
      # Tags subnets for Karpenter auto-discovery
      "karpenter.sh/discovery" = local.cluster_name
    },
    var.private_subnet_tags
  )

  tags = local.tags
}
