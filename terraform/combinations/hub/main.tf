###############################################################################
# Local Variables
###############################################################################
locals {
  # Compute local context tag
  context = "hub"

  # Collect spoke role ARNs from spoke_arn_inputs for cross-account policies
  spoke_role_arns_by_controller = {
    for controller_name in keys(var.ack_configs) : controller_name => compact([
      for spoke_alias, controllers in var.spoke_arn_inputs :
        try(controllers[controller_name].role_arn, "")
    ])
  }
}

###############################################################################
# VPC Module
###############################################################################
module "vpc" {
  source = "../../modules/vpc"

  create = var.enable_vpc

  vpc_name            = var.vpc_name
  vpc_cidr            = var.vpc_cidr
  cluster_name        = var.cluster_name
  enable_nat_gateway  = var.enable_nat_gateway
  single_nat_gateway  = var.single_nat_gateway
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  tags = merge(
    var.tags,
    var.vpc_tags,
    {
      caller_level = "vpc"
    }
  )
}

###############################################################################
# EKS Cluster Module
###############################################################################
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  create = var.enable_vpc && var.enable_eks_cluster

  cluster_name                             = var.cluster_name
  cluster_version                          = var.cluster_version
  vpc_id                                   = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
  subnet_ids                               = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = var.cluster_compute_config

  tags = merge(
    var.tags,
    var.eks_cluster_tags,
    {
      caller_level = "eks_cluster"
    }
  )

  depends_on = [module.vpc]
}

###############################################################################
# ACK Enhanced Pod Identity Module
###############################################################################
module "ack" {
  source = "../../modules/ack-enhanced-pod-identity"

  for_each = var.ack_configs

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_ack && lookup(each.value, "enable_pod_identity", true)

  cluster_name              = var.cluster_name
  service_name              = each.key
  cross_account_policy_json = null
  override_policy_documents = []
  additional_policy_arns    = {}
  trust_policy_conditions   = []

  association_defaults = {
    namespace = lookup(each.value, "namespace", "ack-system")
  }

  associations = {
    default = {
      cluster_name    = var.cluster_name
      service_account = lookup(each.value, "service_account", "ack-${each.key}-controller")
    }
  }

  tags = merge(
    var.tags,
    {
      caller_level = "ack_${each.key}"
      ack_service  = each.key
      context      = local.context
    }
  )

  depends_on = [module.eks_cluster]
}

###############################################################################
# Cross Account Policy Module
###############################################################################
module "cross_account_policy" {
  source = "../../modules/cross-account-policy"

  for_each = var.ack_configs

  create = var.enable_multi_acct && var.enable_ack && lookup(each.value, "enable_pod_identity", true) && length(local.spoke_role_arns_by_controller[each.key]) > 0

  service_name              = each.key
  hub_pod_identity_role_arn = try(module.ack[each.key].role_arn, "")
  spoke_role_arns           = local.spoke_role_arns_by_controller[each.key]

  tags = merge(
    var.tags,
    {
      caller_level = "cross_account_policy_${each.key}"
      ack_service  = each.key
    }
  )

  depends_on = [module.ack]
}

###############################################################################
# ArgoCD Pod Identity Module
###############################################################################
module "argocd_pod_identity" {
  source = "../../modules/argocd-pod-identity"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  cluster_name            = var.cluster_name
  has_inline_policy       = true
  source_policy_documents = [
    file("${path.root}/../../iam/gen3-kro/hub/argocd/recommended-inline-policy")
  ]

  association_defaults = {
    namespace = var.argocd_namespace
  }

  associations = {
    controller = {
      cluster_name    = var.cluster_name
      service_account = "argocd-application-controller"
    }
    server = {
      cluster_name    = var.cluster_name
      service_account = "argocd-server"
    }
    repo-server = {
      cluster_name    = var.cluster_name
      service_account = "argocd-repo-server"
    }
  }

  tags = merge(
    var.tags,
    {
      caller_level = "argocd_pod_identity"
      context      = local.context
    }
  )

  depends_on = [module.eks_cluster]
}

###############################################################################
# Addons Pod Identities Module
###############################################################################
module "addons" {
  source = "../../modules/addons-pod-identities"

  create = var.enable_vpc && var.enable_eks_cluster

  cluster_name  = var.cluster_name
  addon_configs = var.addon_configs

  tags = merge(
    var.tags,
    {
      caller_level = "addons_pod_identities"
      context      = local.context
    }
  )

  depends_on = [module.eks_cluster]
}

###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "../../modules/argocd"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  argocd      = var.argocd_config
  install     = var.argocd_install
  cluster     = var.argocd_cluster
  apps        = var.argocd_apps
  outputs_dir = var.argocd_outputs_dir

  depends_on = [module.eks_cluster, module.addons, module.argocd_pod_identity]
}
