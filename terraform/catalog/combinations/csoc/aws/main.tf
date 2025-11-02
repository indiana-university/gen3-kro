###############################################################################
# Data Sources
###############################################################################
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

###############################################################################
# Local Variables
###############################################################################
locals {

  spoke_role_arns_by_controller = {
    for controller_name in keys(var.addon_configs) : controller_name => compact([
      for spoke_alias, controllers in var.spoke_arn_inputs :
      try(controllers[controller_name].role_arn, "")
    ])
  }
}

###############################################################################
# VPC Module
###############################################################################
module "vpc" {
  source = "../../../modules/aws-vpc"

  create = var.enable_vpc

  vpc_name            = var.vpc_name
  vpc_cidr            = var.vpc_cidr
  cluster_name        = var.cluster_name
  enable_nat_gateway  = var.enable_nat_gateway
  single_nat_gateway  = var.single_nat_gateway
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags
  # Explicit subnet configuration provided via module variables
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs

  tags = merge(
    var.tags,
    var.vpc_tags,
    {
      caller = "csoc"
      module = "vpc"
    }
  )
}

###############################################################################
# EKS Cluster Module
###############################################################################
module "eks_cluster" {
  source = "../../../modules/aws-eks-cluster"

  create = var.enable_vpc && var.enable_k8s_cluster

  cluster_name                             = var.cluster_name
  cluster_version                          = var.cluster_version
  vpc_id                                   = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
  subnet_ids                               = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = var.cluster_compute_config

  tags = merge(
    var.tags,
    var.k8s_cluster_tags,
    {
      caller = "csoc"
      module = "eks_cluster"
    }
  )

  depends_on = [module.vpc]
}

###############################################################################
# IAM Policy Module - Load policies for Pod Identities
###############################################################################
module "iam_policies" {
  source = "../../../modules/iam-policy"

  for_each = var.csoc_iam_policies

  service_name       = each.key
  policy_inline_json = each.value
}

###############################################################################
# Pod Identities Module
###############################################################################
module "pod_identities" {
  source = "../../../modules/aws-pod-identity"

  for_each = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      service_name         = addon_name
      namespace            = lookup(addon_config, "namespace", "kube-system")
      service_account      = lookup(addon_config, "service_account", addon_name)
      custom_inline_policy = null
      enabled              = lookup(addon_config, "enable_identity", false)
    }
    if lookup(addon_config, "enable_identity", false)
  }

  create = var.enable_vpc && var.enable_k8s_cluster && each.value.enabled

  service_name = each.value.service_name
  context      = "csoc"

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account

  custom_inline_policy = each.value.custom_inline_policy

  loaded_inline_policy_document    = try(module.iam_policies[each.key].inline_policy_document, null)
  loaded_override_policy_documents = []
  loaded_managed_policy_arns       = {}
  has_loaded_inline_policy         = try(module.iam_policies[each.key].has_inline_policy, false)

  tags = merge(
    var.tags,
    {
      caller       = "csoc"
      module       = "pod_identities"
      service_name = each.value.service_name
      context      = var.csoc_alias
    }
  )

  depends_on = [module.eks_cluster, module.iam_policies]
}

###############################################################################
# Cross Account Policy Module
###############################################################################
module "cross_account_policy" {
  source = "../../../modules/aws-cross-account-policy"

  for_each = var.addon_configs

  create = var.enable_multi_acct && lookup(each.value, "enable_identity", false) && length(local.spoke_role_arns_by_controller[each.key]) > 0

  service_name                = each.key
  csoc_pod_identity_role_arn = try(module.pod_identities[each.key].role_arn, "")
  spoke_role_arns             = local.spoke_role_arns_by_controller[each.key]

  tags = merge(
    var.tags,
    {
      caller  = "csoc"
      module  = "cross_account_policy"
      service = each.key
    }
  )

  depends_on = [module.pod_identities]
}

###############################################################################
# ArgoCD Enhancement Locals
# Enhance ArgoCD config and apps with default values
###############################################################################
locals {
  csoc_gitops_context = merge(
    {
      provider             = "aws"
      region               = try(data.aws_region.current.id, "")
      aws_region           = try(data.aws_region.current.id, "")
      csoc_repo_url        = try(var.argocd_cluster.metadata.annotations.csoc_repo_url, "")
      csoc_repo_revision   = try(var.argocd_cluster.metadata.annotations.csoc_repo_revision, "main")
      csoc_repo_basepath   = try(var.argocd_cluster.metadata.annotations.csoc_repo_basepath, "argocd")
      addons_repo_url      = try(var.argocd_cluster.metadata.annotations.addons_repo_url, "")
      addons_repo_revision = try(var.argocd_cluster.metadata.annotations.addons_repo_revision, "main")
      addons_repo_basepath = try(var.argocd_cluster.metadata.annotations.addons_repo_basepath, "argocd")
    },
    {}
  )

  addon_config_excluded_keys = [
    "namespace",
    "service_account",
    "enable_identity",
    "enable",
    "enabled",
    "enable_argocd",
    "argocd_chart_version",
    "create_permission",
    "attach_custom_policy",
    "kms_key_arns",
    "secrets_manager_arns",
    "ssm_parameter_arns",
    "parameter_store_arns",
    "inline_policy"
  ]

  csoc_addons_config = {
    for addon_name, addon_config in var.addon_configs : addon_name => merge(
      {
        namespace      = lookup(addon_config, "namespace", addon_name)
        serviceAccount = lookup(addon_config, "service_account", addon_name)
      },
      lookup(addon_config, "enable_identity", false) ? {
        roleArn   = try(module.pod_identities[addon_name].role_arn, "")
        roleName  = try(module.pod_identities[addon_name].role_name, "")
        policyArn = try(module.pod_identities[addon_name].policy_arn, "")
      } : {},
      {
        for config_key, config_val in addon_config :
        config_key => config_val
        if !contains(local.addon_config_excluded_keys, config_key)
      }
    )
  }

  argocd_cluster_annotations_enhanced = merge(
    try(var.argocd_cluster.metadata.annotations, {}),
    {
      "csoc.kro.dev/addons-config"  = yamlencode(local.csoc_addons_config)
      "csoc.kro.dev/gitops-context" = yamlencode(local.csoc_gitops_context)
    }
  )

  argocd_config_enhanced = merge(
    var.argocd_config,
    {
      values = [file("${path.module}/../bootstrap/argocd-initial-values.yaml")]
    }
  )

  argocd_apps_enhanced = merge(
    {
      bootstrap = file("${path.module}/../bootstrap/applicationsets.yaml")
    },
    var.argocd_apps
  )

  # Cluster info for ArgoCD cluster secret
  argocd_cluster_info = {
    name   = var.cluster_name
    server = try(module.eks_cluster.cluster_endpoint, "https://kubernetes.default.svc")
    region = try(data.aws_region.current.id, "")
    eks = {
      version         = try(module.eks_cluster.cluster_version, "")
      endpoint        = try(module.eks_cluster.cluster_endpoint, "")
      oidcProvider    = try(module.eks_cluster.oidc_provider, "")
      oidcProviderArn = try(module.eks_cluster.oidc_provider_arn, "")
    }
  }

  argocd_cluster_enhanced = merge(
    var.argocd_cluster,
    {
      cluster_info = local.argocd_cluster_info
      metadata = merge(
        try(var.argocd_cluster.metadata, {}),
        {
          annotations = local.argocd_cluster_annotations_enhanced
        }
      )
    }
  )
}

###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "../../../modules/argocd"

  create = var.enable_vpc && var.enable_k8s_cluster && var.enable_argocd

  argocd      = local.argocd_config_enhanced
  install     = var.argocd_install
  cluster     = local.argocd_cluster_enhanced
  apps        = local.argocd_apps_enhanced
  outputs_dir = var.argocd_outputs_dir

  depends_on = [module.eks_cluster, module.pod_identities]
}

###############################################################################
# CSOC ConfigMap
###############################################################################
module "csoc_configmap" {
  source = "../../../modules/configmap"

  create           = var.enable_vpc && var.enable_k8s_cluster && var.enable_argocd
  context          = var.csoc_alias
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace
  outputs_dir      = var.argocd_outputs_dir

  pod_identities = {
    for k, v in module.pod_identities : k => {
      role_arn      = v.role_arn
      role_name     = v.role_name
      policy_arn    = v.policy_arn
      service_name  = v.service_name
      policy_source = "csoc_internal"
    }
  }

  # Hub configurations
  addon_configs = var.addon_configs

  # Hub cluster information
  cluster_info = {
    cluster_name              = var.cluster_name
    cluster_endpoint          = try(module.eks_cluster.cluster_endpoint, "")
    region                    = try(data.aws_region.current.id, "")
    account_id                = try(data.aws_caller_identity.current.account_id, "")
    cluster_version           = try(module.eks_cluster.cluster_version, "")
    oidc_provider             = try(module.eks_cluster.oidc_provider, "")
    oidc_provider_arn         = try(module.eks_cluster.oidc_provider_arn, "")
    cluster_security_group_id = try(module.eks_cluster.cluster_security_group_id, "")
    vpc_id                    = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
    private_subnets           = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids
    public_subnets            = var.enable_vpc ? module.vpc.public_subnets : []
  }

  gitops_context = local.csoc_gitops_context

  spokes = {}

  depends_on = [module.eks_cluster, module.pod_identities, module.argocd]
}

###############################################################################
# End of File
###############################################################################
