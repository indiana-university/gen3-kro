output "policy_name" {
  description = "Name of the cross-account IAM policy"
  value       = var.create && length(var.spoke_role_arns) > 0 ? aws_iam_role_policy.cross_account[0].name : null
}

output "policy_id" {
  description = "ID of the cross-account IAM policy"
  value       = var.create && length(var.spoke_role_arns) > 0 ? aws_iam_role_policy.cross_account[0].id : null
}

output "spoke_role_arns" {
  description = "List of spoke role ARNs that can be assumed"
  value       = var.spoke_role_arns
}

output "policy_document" {
  description = "The policy document JSON"
  value       = var.create && length(var.spoke_role_arns) > 0 ? data.aws_iam_policy_document.cross_account[0].json : null
}

output "service_name" {
  description = "ACK service name"
  value       = var.service_name
}

output "hub_role_name" {
  description = "Name of the hub IAM role (extracted from ARN)"
  value       = local.hub_role_name
}
