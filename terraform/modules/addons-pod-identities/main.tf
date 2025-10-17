###################################################################################################################################################
# EKS Addons Pod Identities Module - Streamlined with addon_configs
# Supports only addons defined in config.yaml addon_configs
###################################################################################################################################################

###################################################################################################################################################
# Local Variables
###################################################################################################################################################
locals {
  # Map of addon configurations with enable_pod_identity flag
  enabled_addons = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => addon_config
    if lookup(addon_config, "enable_pod_identity", true)
  }
}

###################################################################################################################################################
# EBS CSI Driver Pod Identity
###################################################################################################################################################
module "ebs_csi_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "ebs_csi") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-ebs-csi-controller"

  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = lookup(local.enabled_addons["ebs_csi"], "kms_arns", ["arn:aws:kms:*:*:key/*"])

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["ebs_csi"], "namespace", "kube-system")
      service_account = lookup(local.enabled_addons["ebs_csi"], "service_account", "ebs-csi-controller-sa")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# External Secrets Pod Identity
###################################################################################################################################################
module "external_secrets_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "external_secrets") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-external-secrets"

  attach_external_secrets_policy              = true
  external_secrets_kms_key_arns               = lookup(local.enabled_addons["external_secrets"], "kms_key_arns", [])
  external_secrets_secrets_manager_arns       = lookup(local.enabled_addons["external_secrets"], "secrets_manager_arns", [])
  external_secrets_ssm_parameter_arns         = lookup(local.enabled_addons["external_secrets"], "ssm_parameter_arns", [])
  external_secrets_secrets_manager_create_permission = lookup(local.enabled_addons["external_secrets"], "create_permission", true)
  attach_custom_policy                        = lookup(local.enabled_addons["external_secrets"], "attach_custom_policy", false)
  policy_statements                           = lookup(local.enabled_addons["external_secrets"], "policy_statements", [])

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["external_secrets"], "namespace", "external-secrets")
      service_account = lookup(local.enabled_addons["external_secrets"], "service_account", "external-secrets")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS Load Balancer Controller Pod Identity
###################################################################################################################################################
module "aws_load_balancer_controller_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "aws_load_balancer_controller") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-load-balancer-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["aws_load_balancer_controller"], "namespace", "kube-system")
      service_account = lookup(local.enabled_addons["aws_load_balancer_controller"], "service_account", "aws-load-balancer-controller")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# AWS EFS CSI Driver Pod Identity
###################################################################################################################################################
module "aws_efs_csi_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "aws_efs_csi") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-aws-efs-csi-controller"

  attach_aws_efs_csi_policy = true

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["aws_efs_csi"], "namespace", "kube-system")
      service_account = lookup(local.enabled_addons["aws_efs_csi"], "service_account", "efs-csi-controller-sa")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Cert Manager Pod Identity
###################################################################################################################################################
module "cert_manager_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "cert_manager") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-cert-manager"

  attach_cert_manager_policy      = true
  cert_manager_hosted_zone_arns   = lookup(local.enabled_addons["cert_manager"], "hosted_zone_arns", [])

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["cert_manager"], "namespace", "cert-manager")
      service_account = lookup(local.enabled_addons["cert_manager"], "service_account", "cert-manager")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# Cluster Autoscaler Pod Identity
###################################################################################################################################################
module "cluster_autoscaler_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "cluster_autoscaler") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-cluster-autoscaler"

  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["cluster_autoscaler"], "namespace", "kube-system")
      service_account = lookup(local.enabled_addons["cluster_autoscaler"], "service_account", "cluster-autoscaler")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# External DNS Pod Identity
###################################################################################################################################################
module "external_dns_pod_identity" {
  count = var.create && contains(keys(local.enabled_addons), "external_dns") ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = lookup(local.enabled_addons["external_dns"], "hosted_zone_arns", [])

  associations = {
    addon = {
      cluster_name    = var.cluster_name
      namespace       = lookup(local.enabled_addons["external_dns"], "namespace", "external-dns")
      service_account = lookup(local.enabled_addons["external_dns"], "service_account", "external-dns")
    }
  }

  tags = var.tags
}

###################################################################################################################################################
# End of File
###################################################################################################################################################
