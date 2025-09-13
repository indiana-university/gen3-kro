###################################################################################################################################################
# VPC, EKS Cluster and IAM Roles & Policies
###################################################################################################################################################
# VPC Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = var.name
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
    "karpenter.sh/discovery" = var.name
  }

  tags = var.tags
}

# EKS Cluster Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name                   = var.name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  tags = {
    Blueprint  = var.name
    GithubRepo = "https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest"
  }
}

# IAM Roles and Policies for ACK controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers
resource "aws_iam_role" "ack_controller" {
  for_each = toset(["iam", "ec2", "eks"])
  name        = "ack-${each.key}-controller-role-mgmt"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowEksAuthToAssumeRoleForPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })
  description = "IRSA role for ACK ${each.key} controller deployment on EKS cluster using Helm charts"
  tags        = var.tags
}

# Then create IAM policies for ACK controllers if the policy is valid
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack_controller_inline_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = can(jsondecode(data.http.inline_policy[each.key].body)) ? data.http.inline_policy[each.key].body : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "${each.key}:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Then attachment policy only when there's a valid policy ARN
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy_attachment" "ack_controller_policy_attachment" {
  for_each = {
    for k, v in var.valid_policies : k => v
    if v != null && can(regex("^arn:aws", v))
  }

  role       = aws_iam_role.ack_controller[each.key].name
  policy_arn = each.value
}

# Cross-account access policy for ACK controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = data.aws_iam_policy_document.ack_controller_cross_account_policy[each.key].json
}



###################################################################################################################################################
# Pod Identities for various addons
###################################################################################################################################################
# EBS CSI EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "aws_ebs_csi_pod_identity" {
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
  count   = var.aws_addons.enable_external_secrets ? 1 : 0
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
  count   = var.aws_addons.enable_aws_load_balancer_controller || var.enable_automode ? 1 : 0
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

# ACK Controllers Pod Identity Association
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_eks_pod_identity_association" "ack_controller" {
  for_each = toset(["iam", "ec2", "eks"])

  cluster_name    = var.cluster_info.cluster_name
  namespace       = "ack-system"
  service_account = "ack-${each.key}-controller"
  role_arn        = aws_iam_role.ack_controller[each.key].arn
}

# Karpenter EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "argocd_hub_pod_identity" {
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
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_ecr_authorization_token" "token" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_ssm_parameter" "private_keys" {
  for_each        = toset(var.private_key_paths)
  name            = each.value
  with_decryption = true
}

# Fetch the recommended policy ARNs
data "http" "policy_arn" {
  for_each = var.policy_arn_urls
  url      = each.value
}

# Fetch the recommended inline policies
data "http" "inline_policy" {
  for_each = var.inline_policy_urls
  url      = each.value
}

data "aws_iam_policy_document" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  statement {
    sid    = "AllowCrossAccountAccess"
    effect = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = [
      for account in split(" ", var.account_ids) : "arn:aws:iam:::role/eks-cluster-mgmt-${each.key}"
    ]
  }
}

###################################################################################################################################################
# End of File
###################################################################################################################################################
