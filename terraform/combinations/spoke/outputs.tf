###############################################################################
# ACK IAM Policy Outputs
###############################################################################
output "ack_iam_policies" {
  description = "Map of ACK IAM policy details (only for controllers with created roles)"
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
  description = "Map of ACK spoke role metadata (created roles + override ARNs)"
  value = merge(
    # Created roles
    {
      for k, v in module.role : k => {
        role_arn    = v.role_arn
        role_name   = v.role_name
        role_source = "created"
      }
    },
    # Override ARNs
    {
      for k, v in local.controllers_using_override : k => {
        role_arn    = lookup(v, "override_arn", "")
        role_name   = "override"
        role_source = "override"
      }
    }
  )
}

output "ack_controllers_using_override" {
  description = "List of ACK controllers using override ARNs (not creating spoke roles)"
  value       = keys(local.controllers_using_override)
}

output "ack_controllers_with_created_roles" {
  description = "List of ACK controllers with created spoke roles"
  value       = keys(local.controllers_needing_roles)
}
