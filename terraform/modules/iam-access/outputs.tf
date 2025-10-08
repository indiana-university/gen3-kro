output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.spoke.account_id
}

output "ack_spoke_role_arns" {
  description = "Spoke ACK Role ARNs (if external spoke is enabled) or ack Hub Role ARNs (if internal spoke is enabled)"
  value = local.enable_external_spoke ? {
      for k, v in aws_iam_role.spoke_ack : k => v.arn
    } : local.enable_internal_spoke ? {
      for k, v in var.ack_hub_roles : k => v.arn
    } : {}
}

