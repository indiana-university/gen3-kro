output "role_arns" {
  description = "Map of role keys to IAM role ARNs"
  value       = { for k, v in aws_iam_role.ack_workload : k => v.arn }
}

output "role_names" {
  description = "Map of role keys to IAM role names"
  value       = { for k, v in aws_iam_role.ack_workload : k => v.name }
}

output "account_id" {
  description = "Spoke AWS account ID"
  value       = data.aws_caller_identity.spoke.account_id
}

output "spoke_alias" {
  description = "Spoke alias used for this module"
  value       = var.spoke_alias
}
