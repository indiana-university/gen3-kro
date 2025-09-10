################################################################################
# EBS CSI EKS Access
################################################################################
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
################################################################################
# External Secrets EKS Access
################################################################################
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
################################################################################
# AWS ALB Ingress Controller EKS Access
################################################################################
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
###################################################################################################################################################
# ACK Controllers Pod Identity Association
###################################################################################################################################################
resource "aws_eks_pod_identity_association" "ack_controller" {
  for_each = toset(["iam", "ec2", "eks"])

  cluster_name    = var.cluster_info.cluster_name
  namespace       = "ack-system"
  service_account = "ack-${each.key}-controller"
  role_arn        = aws_iam_role.ack_controller[each.key].arn
}
################################################################################
# Karpenter EKS Access
################################################################################
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