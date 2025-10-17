###############################################################################
# ACK IAM Policy Outputs
###############################################################################
output "ack_iam_policies" {
  description = "Map of ACK IAM policy details"
  value = var.enable_ack ? {
    for k, v in module.ack_iam_policy : k => {
      has_inline_policy  = v.has_inline_policy
      has_managed_policy = v.has_managed_policy
      policy_arns        = v.policy_arns
    }
  } : {}
}

###############################################################################
# ACK Spoke Role Outputs
###############################################################################
output "ack_spoke_roles" {
  description = "Map of ACK spoke role metadata"
  value = var.enable_ack_spoke_roles ? {
    for k, v in module.ack_spoke_role : k => {
      role_arn  = v.role_arn
      role_name = v.role_name
    }
  } : {}
}

###############################################################################
# Hub Pod Identity Role References
###############################################################################
output "ack_hub_pod_identity_role_arns" {
  description = "Hub ACK pod identity role ARNs referenced by this deployment"
  value       = var.ack_hub_pod_identity_role_arns
}
