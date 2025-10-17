locals {
  ack_services_list = var.enable_ack ? keys(var.ack_services) : []

  ack_spoke_accounts_list = var.enable_ack_spoke_roles ? keys(var.ack_spoke_accounts) : []

  common_tags = merge(
    var.tags,
    {
      Terraform   = "true"
      ClusterName = var.cluster_name
    }
  )
}
