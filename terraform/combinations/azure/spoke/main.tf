locals {
  services_needing_roles = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      hub_principal_id = lookup(var.hub_managed_identities, addon_name, "")
    }
    if lookup(addon_config, "enable_workload_identity", false) &&
       lookup(var.hub_managed_identities, addon_name, "") != ""
  }
}

module "service_policy" {
  source = "../../modules/iam-policy"

  for_each = local.services_needing_roles

  service_name         = each.key
  context              = var.spoke_alias
  provider             = var.provider
  iam_policy_base_path = var.iam_base_path
  repo_root_path       = var.iam_repo_root
}

module "spoke_roles" {
  source = "../../modules/azure-spoke-role"

  for_each = local.services_needing_roles

  create                           = true
  spoke_alias                      = var.spoke_alias
  service_name                     = each.key
  hub_managed_identity_principal_id = each.value.hub_principal_id
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Contributor"  # Default, should be customized per service

  tags = var.tags
}
