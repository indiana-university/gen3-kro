###################################################################################################################################################
# VPC, EKS Cluster and IAM Roles & Policies
###################################################################################################################################################
# VPC Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "vpc" {
  count  = var.enable_eks_hub ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Tags subnets for Karpenter auto-discovery
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# EKS Cluster Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "eks" {
  count = var.enable_eks_hub ? 1 : 0

  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                   = var.cluster_name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc[0].vpc_id
  subnet_ids = module.vpc[0].private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  tags = {
    Blueprint  = var.cluster_name
    GithubRepo = "https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest"
  }
}

###################################################################################################################################################
# Pod Identities for various addons
###################################################################################################################################################
# EBS CSI EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "aws_ebs_csi_pod_identity" {
  count = (var.enable_eks_hub && var.aws_addons.enable_aws_ebs_csi_resources) ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "aws-ebs-csi"

  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = ["arn:aws:kms:*:*:key/*"]

  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = var.cluster_info.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }

  tags = var.tags
}

# External Secrets EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "external_secrets_pod_identity" {
  count = (var.enable_eks_hub && var.aws_addons.enable_external_secrets) ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "external-secrets"

  attach_external_secrets_policy        = true
  external_secrets_kms_key_arns         = ["arn:aws:kms:${var.aws_region}:*:key/${var.cluster_info.cluster_name}/*"]
  external_secrets_secrets_manager_arns = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.cluster_info.cluster_name}/*"]
  external_secrets_ssm_parameter_arns   = ["arn:aws:ssm:${var.aws_region}:*:parameter/${var.cluster_info.cluster_name}/*"]
  external_secrets_create_permission    = false
  attach_custom_policy                  = true
  policy_statements = [
    {
      sid       = "ecr"
      actions   = ["ecr:*"]
      resources = ["*"]
    }
  ]
  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = var.cluster_info.cluster_name
      namespace       = var.external_secrets.namespace
      service_account = var.external_secrets.service_account
    }
  }

  tags = var.tags
}

# AWS ALB Ingress Controller EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "aws_lb_controller_pod_identity" {
count = (var.enable_eks_hub && (var.aws_addons.enable_aws_load_balancer_controller || var.enable_automode)) ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "aws-lbc"

  attach_aws_lb_controller_policy = true


  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = var.cluster_info.cluster_name
      namespace       = var.aws_load_balancer_controller.namespace
      service_account = var.aws_load_balancer_controller.service_account
    }
  }

  tags = var.tags
}


# Karpenter EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "argocd_hub_pod_identity"{
  count   = (var.enable_eks_hub && var.aws_addons.enable_argocd ? 1 : 0)

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name      = "argocd-hub-mgmt"
  use_name_prefix = false

  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "ArgoCD"
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = ["*"]
    }
  ]

  # Pod Identity Associations
  association_defaults = {
    namespace = "argocd"
  }
  associations = {
    controller = {
      cluster_name    = var.cluster_info.cluster_name
      service_account = "argocd-application-controller"
    }
    server = {
      cluster_name    = var.cluster_info.cluster_name
      service_account = "argocd-server"
    }
    repo-server = {
      cluster_name    = var.cluster_info.cluster_name
      service_account = "argocd-repo-server"
    }
  }

  tags = var.tags
}


###################################################################################################################################################
# Data Sources
###################################################################################################################################################
data "aws_caller_identity" "current" {
  count = var.enable_eks_hub ? 1 : 0
}

data "aws_availability_zones" "available" {
  count = var.enable_eks_hub ? 1 : 0
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

###################################################################################################################################################
# End of File
###################################################################################################################################################
