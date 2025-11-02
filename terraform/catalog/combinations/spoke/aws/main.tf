###############################################################################
# Unified IAM Policy Module
###############################################################################
module "service_policy" {
  source = "../../../modules/iam-policy"

  for_each = var.spoke_iam_policies

  service_name       = each.key
  policy_inline_json = each.value
}

###############################################################################
# Unified Spoke Role Module
###############################################################################
module "service_role" {
  source = "../../../modules/aws-spoke-role"

  for_each = local.services_needing_roles

  create = true

  cluster_name               = var.cluster_name
  service_name               = each.key
  spoke_alias                = var.spoke_alias
  csoc_pod_identity_role_arn = each.value.csoc_role_arn

  combined_policy_json = try(module.service_policy[each.key].inline_policy_document, null)
  policy_arns          = {}
  has_inline_policy    = try(module.service_policy[each.key].has_inline_policy, false)
  has_managed_policy   = false

  tags = merge(
    var.tags,
    {
      caller_level = "spoke_service_role_${each.key}"
      service_name = each.key
      spoke_alias  = var.spoke_alias
      context      = "spoke"
    }
  )

  depends_on = [module.service_policy]
}

###############################################################################
# ArgoCD ConfigMap per Spoke
###############################################################################
module "argocd_configmap" {
  source = "../../../modules/configmap"

  create           = var.enable_argocd && var.enable_vpc && var.enable_k8s_cluster
  context          = var.spoke_alias
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace
  outputs_dir      = var.outputs_dir

  # For multi-account: ConfigMap contains hub's pod identity role ARNs
  # The hub's pod identities will assume the spoke roles via cross-account policies
  pod_identities = merge(
    {
      # Services with created spoke roles: use hub's pod identity role ARN
      for k, v in module.service_role : k => {
        role_arn      = lookup(var.csoc_pod_identity_arns, k, "")  # Hub's pod identity role ARN
        role_name     = split("/", lookup(var.csoc_pod_identity_arns, k, "unknown"))[length(split("/", lookup(var.csoc_pod_identity_arns, k, "unknown"))) - 1]
        policy_arn    = ""
        service_name  = k
        policy_source = "hub_pod_identity"
      }
    },
    {
      # Services with override ARNs: use the override ARN directly
      for k, v in local.services_using_override : k => {
        role_arn      = lookup(v, "override_arn", "")
        role_name     = split("/", lookup(v, "override_arn", "unknown"))[length(split("/", lookup(v, "override_arn", "unknown"))) - 1]
        policy_arn    = ""
        service_name  = k
        policy_source = "spoke_override"
      }
    }
  )

  addon_configs = var.csoc_addon_configs

  cluster_info = var.cluster_info

  gitops_context = merge(
    var.csoc_cluster_secret_annotations,
    {
      spoke_alias  = var.spoke_alias
      spoke_region = var.region
    }
  )

  spokes = {}

  depends_on = [module.service_role]
}

###############################################################################
# End of File
###############################################################################
