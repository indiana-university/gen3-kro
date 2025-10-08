###################################################################################################################################################
# VPC, EKS Cluster and IAM Roles & Policies
###################################################################################################################################################
# VPC Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "vpc" {
  count  = var.create ? 1 : 0

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

  tags = local.resource_tags
}

# EKS Cluster Module
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "eks" {
  count = var.create ? 1 : 0

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

  tags = local.resource_tags
}

###################################################################################################################################################
# Pod Identities for various addons
###################################################################################################################################################
# EBS CSI EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "aws_ebs_csi_pod_identity" {
  count = (var.create && var.aws_addons.enable_aws_ebs_csi_resources) ? 1 : 0

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

  tags = local.resource_tags
}

# External Secrets EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "external_secrets_pod_identity" {
  count = (var.create && var.aws_addons.enable_external_secrets) ? 1 : 0

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

  tags = local.resource_tags
}

# AWS ALB Ingress Controller EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "aws_lb_controller_pod_identity" {
  count = (var.create && (var.aws_addons.enable_aws_load_balancer_controller || var.enable_automode)) ? 1 : 0

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

  tags = local.resource_tags
}


# Karpenter EKS Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
module "argocd_hub_pod_identity"{
  count   = (var.create && var.oss_addons.enable_argocd ? 1 : 0)

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

  tags = local.resource_tags
}

###################################################################################################################################################
# Data Sources
###################################################################################################################################################
data "aws_caller_identity" "current" {
  count = var.create ? 1 : 0
}

data "aws_availability_zones" "available" {
  count = var.create ? 1 : 0
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks[0].cluster_name
  count = var.create ? 1 : 0
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# ACK Controllers' Pod Identity Association
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_eks_pod_identity_association" "ack" {
  for_each = var.create ? var.ack_services_config : {}

  cluster_name    = var.cluster_info.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.hub_ack[each.key].arn
}

# Hub account ACK roles
resource "aws_iam_role" "hub_ack" {
  for_each = var.create ? toset(var.ack_services) : []
  name     = "${var.hub_alias}-ack-${each.key}-role"

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
  description = "Hub role for ${var.cluster_info.cluster_name} ${each.key}-ack-controller - for all Spokes"
  tags        = local.resource_tags
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# IAM Policies for ACK Controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack" {
  for_each = var.create ? local.services_with_inline : {}

  role   = aws_iam_role.hub_ack[each.key].name
  policy = trimspace(local.chosen_inline_policies[each.key])

}

resource "aws_iam_role_policy_attachment" "ack" {
  for_each = var.create ? local.services_with_arn : {}

  role       = aws_iam_role.hub_ack[each.key].name
  policy_arn = local.chosen_policy_arns[each.key]
}

###################################################################################################################################################
# Locals
###################################################################################################################################################
locals {
  resource_tags = merge(
    var.tags,
    {
      ClusterAlias   = var.hub_alias
      ClusterName = var.cluster_name
    }
  )
  /// Determininistic policy selection logic
  /// Priority: User-provided inline policy >
  ///           Recommended policy ARN >
  ///           Recommended inline policy >
  ///           Default to AWS ReadOnlyAccess

  chosen_inline_policies = {
    for service in var.ack_services :
      service =>
      try(data.http.user_inline_policy[service].status_code == 200 ? data.http.user_inline_policy[service].body : null, null) != null ? try(data.http.user_inline_policy[service].body, null) :
      data.http.recommended_policy_arn[service].status_code    == 200 ? null                                              :
      data.http.recommended_inline_policy[service].status_code == 200 ? data.http.recommended_inline_policy[service].body :
                                                                        null
  }

  chosen_policy_arns = {
    for service in var.ack_services :
      service =>
      local.chosen_inline_policies[service]                 != null ? null                                                      :
      data.http.recommended_policy_arn[service].status_code == 200  ? trimspace(data.http.recommended_policy_arn[service].body) :
                                                                      "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  # Services that have a valid JSON inline policy
  services_with_inline = {
    for s in var.ack_services :
    s => s
    if local.chosen_inline_policies[s] != null && can(jsondecode(local.chosen_inline_policies[s]))
  }

  # Services that should attach a managed policy ARN
  services_with_arn = {
    for s in var.ack_services :
    s => s
    if local.chosen_policy_arns[s] != null
  }
}

data "http" "user_inline_policy" {
  for_each = var.user_provided_inline_policy_link != "" ? toset(var.ack_services) : []
  url      = "${var.user_provided_inline_policy_link}/${each.key}.json"
}

# Fetch the recommended policy ARNs
data "http" "recommended_policy_arn" {
  for_each = toset(var.ack_services)
  url      = "https://raw.githubusercontent.com/aws-controllers-k8s/${each.key}-controller/main/config/iam/recommended-policy-arn"
}

# Fetch the recommended inline policies
data "http" "recommended_inline_policy" {
  for_each = toset(var.ack_services)
  url      = "https://raw.githubusercontent.com/aws-controllers-k8s/${each.key}-controller/main/config/iam/recommended-inline-policy"
}

###################################################################################################################################################
# End of File
###################################################################################################################################################
