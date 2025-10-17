output "role_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM role associated with the Pod Identity"
  value       = try(module.pod_identity[0].iam_role_arn, null)
}

output "role_name" {
  description = "The name of the IAM role associated with the Pod Identity"
  value       = try(module.pod_identity[0].iam_role_name, null)
}

output "role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(module.pod_identity[0].iam_role_unique_id, null)
}

output "associations" {
  description = "Map of Pod Identity associations created"
  value       = try(module.pod_identity[0].associations, {})
}

output "policy_arns" {
  description = "Map of policy ARNs attached to the pod identity"
  value       = local.all_policy_arns
}

output "has_inline_policy" {
  description = "Whether the pod identity has inline policies attached"
  value       = local.has_inline_policy
}
