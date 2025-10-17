locals {
  # Filter enabled controllers
  enabled_controllers = {
    for k, v in var.ack_configs : k => v
    if lookup(v, "enable_pod_identity", true)
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
