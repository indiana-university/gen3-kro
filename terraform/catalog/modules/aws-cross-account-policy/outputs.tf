output "policy_name" {
  description = "Name of the cross-account IAM policy"
  value       = var.create ? aws_iam_role_policy.cross_account[0].name : null
}

output "policy_id" {
  description = "ID of the cross-account IAM policy"
  value       = var.create ? aws_iam_role_policy.cross_account[0].id : null
}

# Alias for policy_id to maintain compatibility
output "policy_arn" {
  description = "ID of the cross-account IAM policy (inline policies don't have ARNs, this returns the policy ID)"
  value       = var.create ? aws_iam_role_policy.cross_account[0].id : null
}

output "spoke_role_arns" {
  description = "List of spoke role ARNs that can be assumed"
  value       = var.spoke_role_arns
}

output "policy_document" {
  description = "The policy document JSON"
  value       = var.create ? data.aws_iam_policy_document.cross_account[0].json : null
}

output "service_name" {
  description = "ACK service name"
  value       = var.service_name
}

output "csoc_role_name" {
  description = "Name of the CSOC IAM role (extracted from ARN)"
  value       = local.csoc_role_name
}
