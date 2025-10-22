###############################################################################
# Unified IAM Policy Module
# Creates policies for all services (ACKs + Addons) that need role creation
###############################################################################
module "service_policy" {
  source = "../../modules/iam-policy"

  for_each = local.services_needing_roles

  service_type         = each.value.service_type
  service_name         = each.key
  context              = "spoke-${var.spoke_alias}"
  iam_policy_repo_url  = var.iam_git_repo_url
  iam_policy_branch    = var.iam_git_branch
  iam_policy_base_path = var.iam_base_path
  iam_raw_base_url     = var.iam_raw_base_url
  repo_root_path       = var.iam_repo_root != "" ? var.iam_repo_root : "${path.root}/../../../.."
}

###############################################################################
# Unified Spoke Role Module
# Creates roles for all services (ACKs + Addons) that need role creation
###############################################################################
module "service_role" {
  source = "../../modules/spoke-role"

  for_each = local.services_needing_roles

  create = true

  service_type              = each.value.service_type
  cluster_name              = var.cluster_name
  service_name              = each.key
  spoke_alias               = var.spoke_alias
  hub_pod_identity_role_arn = each.value.hub_role_arn

  # Get loaded policy from iam-policy module
  combined_policy_json = try(module.service_policy[each.key].inline_policy_document, null)
  policy_arns          = try(module.service_policy[each.key].managed_policy_arns, {})
  has_inline_policy    = try(module.service_policy[each.key].has_inline_policy, false)
  has_managed_policy   = try(module.service_policy[each.key].has_managed_policies, false)

  tags = merge(
    var.tags,
    {
      caller_level = "spoke_service_role_${each.key}"
      service_name = each.key
      service_type = each.value.service_type
      spoke_alias  = var.spoke_alias
      context      = "spoke"
    }
  )

  depends_on = [module.service_policy]
}

###############################################################################
# ArgoCD ConfigMap per Spoke
# Creates a ConfigMap with spoke-specific configuration for ArgoCD
###############################################################################
module "argocd_configmap" {
  source = "../../modules/spokes-configmap"

  create           = true
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  # Pass all role information (created + overrides)
  pod_identities = merge(
    # Roles created by this spoke
    {
      for k, v in module.service_role : k => {
        role_arn      = v.role_arn
        role_name     = v.role_name
        policy_arn    = ""  # Spoke roles use inline policies, not managed policies
        service_type  = lookup(local.services_needing_roles[k], "service_type", "unknown")
        service_name  = k
        policy_source = "spoke_created"
      }
    },
    # Roles using override ARNs
    {
      for k, v in local.services_using_override : k => {
        role_arn      = lookup(v, "override_arn", "")
        role_name     = split("/", lookup(v, "override_arn", "unknown"))[length(split("/", lookup(v, "override_arn", "unknown"))) - 1]
        policy_arn    = ""
        service_type  = lookup(v, "service_type", "unknown")
        service_name  = k
        policy_source = "spoke_override"
      }
    }
  )

  # Pass configurations
  ack_configs   = var.ack_configs
  addon_configs = var.addon_configs

  # Cluster information (if available)
  cluster_info = var.cluster_info

  # GitOps context
  gitops_context = {
    spoke_alias  = var.spoke_alias
    spoke_region = var.region
    git_repo     = var.iam_git_repo_url
    git_branch   = var.iam_git_branch
  }

  # Empty spokes map for spoke-level configmap (spokes info managed at hub level)
  spokes = {}

  depends_on = [module.service_role]
}

###############################################################################
# End of File
###############################################################################
