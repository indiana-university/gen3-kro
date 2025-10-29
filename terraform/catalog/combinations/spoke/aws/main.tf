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
  source = "../../../modules/spokes-configmap"

  create           = true
  context          = var.spoke_alias
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  pod_identities = merge(
    {
      for k, v in module.service_role : k => {
        role_arn      = v.role_arn
        role_name     = v.role_name
        policy_arn    = ""
        service_name  = k
        policy_source = "spoke_created"
      }
    },
    {
      for k, v in local.services_using_override : k => {
        role_arn      = lookup(v, "override_arn", "")
        role_name     = split("/", lookup(v, "override_arn", "unknown"))[length(split("/", lookup(v, "override_arn", "unknown"))) - 1]
        policy_arn    = ""
        service_name  = k
        policy_source = "spoke_override"
      }
    }
  )

  addon_configs = var.addon_configs

  cluster_info = var.cluster_info

  gitops_context = {
    spoke_alias  = var.spoke_alias
    spoke_region = var.region
    git_repo     = ""
    git_branch   = ""
  }

  spokes = {}

  depends_on = [module.service_role]
}

###############################################################################
# End of File
###############################################################################
