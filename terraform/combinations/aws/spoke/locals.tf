locals {
  # Filter enabled services (treated as addons)
  enabled_addons = {
    for k, v in var.addon_configs : k => v
    if lookup(v, "enable_pod_identity", true)
  }

  # All enabled services with metadata
  all_enabled_services = {
    for k, v in local.enabled_addons : k => merge(v, {
      hub_role_arn = lookup(var.hub_pod_identity_arns, k, "")
    })
  }

  # Filter all services that need role creation (no override_arn provided)
  services_needing_roles = {
    for k, v in local.all_enabled_services : k => v
    if lookup(v, "override_arn", "") == ""
  }

  # Filter all services using override ARNs (skip role creation)
  services_using_override = {
    for k, v in local.all_enabled_services : k => v
    if lookup(v, "override_arn", "") != ""
  }

  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      ClusterName = var.cluster_name
      Spoke       = var.spoke_alias
    }
  )
}
