###############################################################################
# ACK IAM Policy Module
###############################################################################
module "policy" {
  source = "../../modules/ack-iam-policy"

  for_each = local.enabled_controllers

  create = true

  service_name           = each.key
  override_policy_path   = ""
  override_policy_url    = ""
  additional_policy_arns = {}
}

###############################################################################
# ACK Spoke Role Module
###############################################################################
module "role" {
  source = "../../modules/ack-spoke-role"

  for_each = local.enabled_controllers

  create = true

  cluster_name              = var.cluster_name
  service_name              = each.key
  spoke_alias               = var.spoke_alias
  hub_pod_identity_role_arn = "" # Will be populated by hub via cross-account policy
  combined_policy_json      = try(module.policy[each.key].combined_policy_json, null)
  policy_arns               = try(module.policy[each.key].policy_arns, {})
  has_inline_policy         = try(module.policy[each.key].has_inline_policy, false)
  has_managed_policy        = try(module.policy[each.key].has_managed_policy, false)

  tags = merge(
    var.tags,
    {
      caller_level = "spoke_role_${each.key}"
      ack_service  = each.key
      spoke_alias  = var.spoke_alias
      context      = "spoke"
    }
  )

  depends_on = [module.policy]
}

###############################################################################
# End of File
###############################################################################
