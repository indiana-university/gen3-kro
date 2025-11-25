output "role_arn" {
  description = "ARN of the spoke account IAM role"
  value       = var.override_id != null ? var.override_id : (var.create ? aws_iam_role.spoke[0].arn : null)
}

output "role_name" {
  description = "Name of the spoke account IAM role"
  value       = var.override_id != null ? null : (var.create ? aws_iam_role.spoke[0].name : null)
}

output "role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = var.override_id != null ? null : (var.create ? aws_iam_role.spoke[0].unique_id : null)
}

output "service_name" {
  description = "Service name"
  value       = var.service_name
}

output "spoke_alias" {
  description = "Spoke account alias"
  value       = var.spoke_alias
}
