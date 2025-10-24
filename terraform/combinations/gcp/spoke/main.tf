locals {
  services_needing_roles = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      hub_sa_email = lookup(var.hub_service_accounts, addon_name, "")
    }
    if lookup(addon_config, "enable_workload_identity", false) &&
       lookup(var.hub_service_accounts, addon_name, "") != ""
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
  source = "../../modules/gcp-spoke-role"

  for_each = local.services_needing_roles

  create                    = true
  spoke_alias               = var.spoke_alias
  service_name              = each.key
  project_id                = var.project_id
  hub_service_account_email = each.value.hub_sa_email
  roles                     = ["roles/viewer"]  # Default, should be customized per service
}
