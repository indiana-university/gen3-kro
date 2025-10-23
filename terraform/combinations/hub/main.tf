###############################################################################
# Data Sources
###############################################################################
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

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

  vpc_name               = var.vpc_name
  vpc_cidr               = var.vpc_cidr
  cluster_name           = var.cluster_name
  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  public_subnet_tags     = var.public_subnet_tags
  private_subnet_tags    = var.private_subnet_tags
  # Explicit subnet configuration provided via module variables
  availability_zones     = var.availability_zones
  private_subnet_cidrs   = var.private_subnet_cidrs
  public_subnet_cidrs    = var.public_subnet_cidrs

  tags = merge(
    var.tags,
    var.vpc_tags,
    {
      caller     = "hub"
      module     = "vpc"
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
      caller     = "hub"
      module     = "eks_cluster"
    }
  )

  depends_on = [module.vpc]
}

###############################################################################
# IAM Policy Module - Load policies for Pod Identities
###############################################################################
module "iam_policies" {
  source = "../../modules/iam-policy"

  for_each = merge(
    # ACK services
    {
      for svc_name, svc_config in var.ack_configs :
      "ack-${svc_name}" => {
        service_type = "acks"
        service_name = svc_name
      }
      if var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
    },

    # Addons
    {
      for addon_name, addon_config in var.addon_configs :
      "${addon_name}" => {
        service_type = "addons"
        service_name = addon_name
      }
      if lookup(addon_config, "enable_pod_identity", false)
    }
  )

  service_type         = each.value.service_type
  service_name         = each.value.service_name
  context              = "hub"
  iam_policy_base_path = var.iam_base_path
  iam_raw_base_url     = var.iam_raw_base_url
  repo_root_path       = var.iam_repo_root != "" ? var.iam_repo_root : "${path.root}/../../../.."
}

###############################################################################
# Pod Identities Module (Unified: ACK, ArgoCD, Addons)
###############################################################################
module "pod_identities" {
  source = "../../modules/pod-identity"

  for_each = merge(
    # ACK services
    {
      for svc_name, svc_config in var.ack_configs :
      "ack-${svc_name}" => {
        service_type         = "acks"  # folder name is plural: iam/gen3/<hub_alias>/acks/
        service_name         = svc_name
        namespace            = lookup(svc_config, "namespace", "ack-system")
        service_account      = lookup(svc_config, "service_account", "ack-${svc_name}-sa")
        custom_inline_policy = null
        enabled              = var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
      }
      if var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
    },

    # Addons
    {
      for addon_name, addon_config in var.addon_configs :
      "${addon_name}" => {
        service_type         = "addons"  # folder name is plural: iam/gen3/<hub_alias>/addons/
        service_name         = addon_name
        namespace            = lookup(addon_config, "namespace", "kube-system")
        service_account      = lookup(addon_config, "service_account", addon_name)
        custom_inline_policy = null
        enabled              = lookup(addon_config, "enable_pod_identity", false)
      }
      if lookup(addon_config, "enable_pod_identity", false)
    }
  )

  create = var.enable_vpc && var.enable_eks_cluster && each.value.enabled

  # Service identification
  service_type = each.value.service_type
  service_name = each.value.service_name
  context      = "hub"

  # Cluster and namespace configuration
  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account

  # Custom inline policy (for ArgoCD or custom services)
  custom_inline_policy = each.value.custom_inline_policy

  # Loaded IAM policies from iam_policies module
  loaded_inline_policy_document   = try(module.iam_policies[each.key].inline_policy_document, null)
  loaded_override_policy_documents = try(module.iam_policies[each.key].override_policy_documents, [])
  loaded_managed_policy_arns       = try(module.iam_policies[each.key].managed_policy_arns, {})
  has_loaded_inline_policy         = try(module.iam_policies[each.key].has_inline_policy, false)

  tags = merge(
    var.tags,
    {
      caller       = "hub"
      module       = "pod_identities"
      service_type = each.value.service_type
      service_name = each.value.service_name
      context      = local.context
    }
  )

  depends_on = [module.eks_cluster, module.iam_policies]
}

###############################################################################
# Cross Account Policy Module
###############################################################################
module "cross_account_policy" {
  source = "../../modules/cross-account-policy"

  for_each = var.ack_configs

  create = var.enable_multi_acct && var.enable_ack && lookup(each.value, "enable_pod_identity", true) && length(local.spoke_role_arns_by_controller[each.key]) > 0

  service_name              = each.key
  hub_pod_identity_role_arn = try(module.pod_identities["ack-${each.key}"].role_arn, "")
  spoke_role_arns           = local.spoke_role_arns_by_controller[each.key]

  tags = merge(
    var.tags,
    {
      caller  = "hub"
      module  = "cross_account_policy"
      service = each.key
    }
  )

  depends_on = [module.pod_identities]
}

###############################################################################
# ArgoCD Cluster Configuration Enhancement
###############################################################################
locals {
  # Build enhanced argocd_cluster with IAM role ARN annotations
  argocd_cluster_enhanced = merge(
    var.argocd_cluster,
    {
      metadata = merge(
        lookup(var.argocd_cluster, "metadata", {}),
        {
          annotations = merge(
            lookup(lookup(var.argocd_cluster, "metadata", {}), "annotations", {}),
            # ACK controller hub role ARN annotations
            {
              for k, v in module.pod_identities :
              "ack_${replace(k, "ack-", "")}_hub_role_arn" => v.role_arn
              if startswith(k, "ack-")
            },
            # Addon hub role ARN annotations
            {
              for k, v in module.pod_identities :
              "${replace(k, "_", "-")}_irsa_role_arn" => v.role_arn
              if !startswith(k, "ack-")
            }
            # Note: Spoke role ARNs will be available via outputs and can be queried
            # They are not added to hub configmap to keep concerns separated
          )
        }
      )
    }
  )

  # Enhanced ArgoCD config with initial values
  argocd_config_enhanced = merge(
    var.argocd_config,
    {
      values = [file("${path.module}/argocd-initial-values.yaml")]
    }
  )

  # Merge bootstrap applicationsets with apps from terragrunt
  argocd_apps_enhanced = merge(
    {
      bootstrap = file("${path.module}/applicationsets.yaml")
    },
    var.argocd_apps
  )
}

###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "../../modules/argocd"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  argocd      = local.argocd_config_enhanced
  install     = var.argocd_install
  cluster     = local.argocd_cluster_enhanced
  apps        = local.argocd_apps_enhanced
  outputs_dir = var.argocd_outputs_dir

  depends_on = [module.eks_cluster, module.pod_identities]
}

###############################################################################
# Hub ConfigMap for ArgoCD
# Creates a configmap with hub-specific configuration that ArgoCD
# ApplicationSets can query for IAM roles, namespaces, and cluster info.
###############################################################################
module "hub_configmap" {
  source = "../../modules/spokes-configmap"

  create           = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

    # Hub pod identities (ACK controllers + addons)
  pod_identities = {
    for k, v in module.pod_identities : k => {
      role_arn      = v.role_arn
      role_name     = v.role_name
      policy_arn    = v.policy_arn
      service_type  = v.service_type
      service_name  = v.service_name
      policy_source = "hub_internal"
    }
  }

  # Hub configurations
  ack_configs   = var.ack_configs
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

  # GitOps context for hub (from ArgoCD cluster annotations)
  gitops_context = {
    hub_repo_url      = try(var.argocd_cluster.metadata.annotations.hub_repo_url, "")
    hub_repo_revision = try(var.argocd_cluster.metadata.annotations.hub_repo_revision, "main")
    hub_repo_basepath = try(var.argocd_cluster.metadata.annotations.hub_repo_basepath, "argocd")
    aws_region        = try(data.aws_region.current.id, "")
  }

  # No spokes data in hub configmap (spokes manage their own)
  spokes = {}

  depends_on = [module.eks_cluster, module.pod_identities, module.argocd]
}
