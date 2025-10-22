###################################################################################################################################################
# EKS Cluster Module
###################################################################################################################################################
module "eks" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/eks/aws"
  version = "21.4.0"

  name                             = var.cluster_name
  kubernetes_version               = var.cluster_version
  endpoint_public_access           = var.cluster_endpoint_public_access

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  compute_config = var.cluster_compute_config

  tags = var.tags
}

###################################################################################################################################################
# Data Sources
###################################################################################################################################################
data "aws_caller_identity" "current" {
  count = var.create ? 1 : 0
}

