###############################################################################
# Local Variables
# Compute addon configurations, service role requirements, and common tags
###############################################################################
locals {
  # Filter enabled addons based on enable_identity flag
  enabled_addons = {
    for k, v in var.addon_configs : k => v
    if lookup(v, "enable_identity", true)
  }

  # Merge CSOC role ARNs into enabled services configuration
  all_enabled_services = {
    for k, v in local.enabled_addons : k => merge(v, {
      csoc_role_arn = lookup(var.csoc_pod_identity_arns, k, "")
    })
  }

  # Services that need new IAM roles created (no override ARN provided)
  services_needing_roles = {
    for k, v in local.all_enabled_services : k => v
    if lookup(v, "override_arn", "") == ""
  }

  # Services using existing/override ARN instead of creating new roles
  services_using_override = {
    for k, v in local.all_enabled_services : k => v
    if lookup(v, "override_arn", "") != ""
  }

  # Common tags applied to all spoke resources
  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      ClusterName = var.cluster_name
      Spoke       = var.spoke_alias
    }
  )
}

###############################################################################
# End of File
###############################################################################
