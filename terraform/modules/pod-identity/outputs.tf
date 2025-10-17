output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = var.create ? module.pod_identity[0].iam_role_arn : null
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = var.create ? module.pod_identity[0].iam_role_name : null
}

output "iam_role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = var.create ? module.pod_identity[0].iam_role_unique_id : null
}

output "associations" {
  description = "Map of pod identity associations created and their attributes"
  value       = var.create ? module.pod_identity[0].associations : {}
}

output "service_name" {
  description = "ACK service name"
  value       = var.service_name
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}
