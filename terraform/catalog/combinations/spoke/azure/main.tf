###############################################################################
# Local Variables
###############################################################################
locals {
  # Services that need roles created in the spoke account
  services_needing_roles = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      hub_principal_id = lookup(var.csoc_pod_identity_arns, addon_name, "")
    }
    if lookup(addon_config, "enable_identity", false) &&
    lookup(var.csoc_pod_identity_arns, addon_name, "") != ""
  }

  # Services using override identities (not creating new roles)
  services_using_override = {}
}

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
  source = "../../../modules/azure-spoke-role"

  for_each = local.services_needing_roles

  create = true

  service_name                      = each.key
  spoke_alias                       = var.spoke_alias
  hub_managed_identity_principal_id = each.value.hub_principal_id
  scope                             = "/subscriptions/${var.subscription_id}"
  role_definition_name              = "Contributor"
  custom_role_definition_id         = ""

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

  pod_identities = merge(
    {
      for k, v in module.service_role : k => {
        role_arn      = "" # Not applicable for Azure
        role_name     = "${var.spoke_alias}-${k}"
        policy_arn    = "" # Not applicable for Azure
        service_name  = k
        policy_source = "spoke_created"
        principal_id  = lookup(local.services_needing_roles[k], "hub_principal_id", "")
      }
    },
    {
      for k, v in local.services_using_override : k => {
        role_arn      = "" # Not applicable for Azure
        role_name     = "override"
        policy_arn    = "" # Not applicable for Azure
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


