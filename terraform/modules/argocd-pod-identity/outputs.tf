output "role_arn" {
  description = "The Amazon Resource Name (ARN) of the IAM role associated with the Pod Identity"
  value       = try(module.argocd_pod_identity[0].iam_role_arn, null)
}

output "role_name" {
  description = "The name of the IAM role associated with the Pod Identity"
  value       = try(module.argocd_pod_identity[0].iam_role_name, null)
}

output "role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(module.argocd_pod_identity[0].iam_role_unique_id, null)
}

output "associations" {
  description = "Map of Pod Identity associations created"
  value       = try(module.argocd_pod_identity[0].associations, {})
}
