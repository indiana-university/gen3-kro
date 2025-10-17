###############################################################################
# ACK IAM Policy Module
###############################################################################
module "policy" {
  source = "../../modules/ack-iam-policy"

  for_each = var.ack_services

  create = var.enable_ack && lookup(each.value, "enabled", true)

  service_name           = each.key
  override_policy_path   = lookup(each.value, "override_policy_path", "")
  override_policy_url    = lookup(each.value, "override_policy_url", "")
  additional_policy_arns = lookup(each.value, "additional_policy_arns", {})
}

###############################################################################
# ACK Spoke Role Module
###############################################################################
module "role" {
  source = "../../modules/ack-spoke-role"

  for_each = var.ack_spoke_accounts

  create = var.enable_ack_spoke_roles && lookup(each.value, "enabled", true)

  cluster_name              = var.cluster_name
  service_name              = each.value.service_name
  spoke_alias               = lookup(each.value, "spoke_alias", each.key)
  hub_pod_identity_role_arn = lookup(var.ack_hub_pod_identity_role_arns, each.value.service_name, "")
  combined_policy_json      = try(module.policy[each.value.service_name].combined_policy_json, null)
  policy_arns               = try(module.policy[each.value.service_name].policy_arns, {})
  has_inline_policy         = try(module.policy[each.value.service_name].has_inline_policy, false)
  has_managed_policy        = try(module.policy[each.value.service_name].has_managed_policy, false)

  tags = merge(
    var.tags,
    var.ack_spoke_tags,
    lookup(each.value, "tags", {})
  )

  depends_on = [module.policy]
}

###############################################################################
# End of File
###############################################################################
