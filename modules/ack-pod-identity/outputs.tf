output "iam_role_arn" {
  description = "IAM Role ARN for the ACK pod identity"
  value       = var.create ? module.ack_pod_identity[0].iam_role_arn : null
}

output "iam_role_name" {
  description = "IAM Role name for the ACK pod identity"
  value       = var.create ? module.ack_pod_identity[0].iam_role_name : null
}

output "iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = var.create ? module.ack_pod_identity[0].iam_role_unique_id : null
}

output "associations" {
  description = "Map of pod identity associations"
  value       = var.create ? module.ack_pod_identity[0].associations : {}
}

output "service_name" {
  description = "ACK service name"
  value       = var.service_name
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}
