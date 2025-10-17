###############################################################################
# ACK IAM Policy Outputs
###############################################################################
output "ack_iam_policies" {
  description = "Map of ACK IAM policy details"
  value = {
    for k, v in module.policy : k => {
      has_inline_policy  = v.has_inline_policy
      has_managed_policy = v.has_managed_policy
      policy_arns        = v.policy_arns
    }
  }
}

###############################################################################
# ACK Spoke Role Outputs
###############################################################################
output "ack_spoke_roles" {
  description = "Map of ACK spoke role metadata"
  value = {
    for k, v in module.role : k => {
      role_arn  = v.role_arn
      role_name = v.role_name
    }
  }
}

