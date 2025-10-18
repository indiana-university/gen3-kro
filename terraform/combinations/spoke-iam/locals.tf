locals {
  # Filter enabled controllers
  enabled_controllers = {
    for k, v in var.ack_configs : k => v
    if lookup(v, "enable_pod_identity", true)
  }

  # Filter controllers that need role creation (no override_arn provided)
  controllers_needing_roles = {
    for k, v in local.enabled_controllers : k => v
    if lookup(v, "override_arn", "") == ""
  }

  # Filter controllers using override ARNs (skip role creation)
  controllers_using_override = {
    for k, v in local.enabled_controllers : k => v
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
