###################################################################################################################################################
# EKS Cluster Module
###################################################################################################################################################
module "eks" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  cluster_compute_config = var.cluster_compute_config

  tags = var.tags
}

# Lifecycle protection for cluster rename scenarios
resource "null_resource" "cluster_lifecycle_protection" {
  count = var.create ? 1 : 0

  triggers = {
    cluster_name = var.cluster_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

###################################################################################################################################################
# Data Sources
###################################################################################################################################################
data "aws_caller_identity" "current" {
  count = var.create ? 1 : 0
}

data "aws_eks_cluster_auth" "this" {
  count = var.create ? 1 : 0
  name  = module.eks[0].cluster_name
}

