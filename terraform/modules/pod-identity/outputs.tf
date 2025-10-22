###################################################################################################################################################
# Pod Identity Module Outputs
###################################################################################################################################################
output "role_arn" {
  description = "ARN of the IAM role for pod identity"
  value       = var.create ? module.pod_identity[0].iam_role_arn : null
}

output "role_name" {
  description = "Name of the IAM role for pod identity"
  value       = var.create ? module.pod_identity[0].iam_role_name : null
}

output "role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = var.create ? module.pod_identity[0].iam_role_unique_id : null
}

output "policy_arn" {
  description = "ARN of the IAM policy (if custom policy was attached)"
  value       = var.create ? try(module.pod_identity[0].iam_policy_arn, null) : null
}

output "policy_name" {
  description = "Name of the IAM policy (if custom policy was attached)"
  value       = var.create ? try(module.pod_identity[0].iam_policy_name, null) : null
}

output "associations" {
  description = "Map of pod identity associations created"
  value       = var.create ? module.pod_identity[0].associations : {}
}

output "policy_source" {
  description = "Source of the IAM policy (loaded, custom, or none)"
  value       = local.use_custom_policies ? "custom" : (local.use_loaded_policies ? "loaded" : "none")
}

output "service_type" {
  description = "Type of service (ack, addon, argocd, custom)"
  value       = var.service_type
}

output "service_name" {
  description = "Name of the service"
  value       = var.service_name
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "debug_policy_info" {
  description = "Debug: Policy loading information"
  value = {
    use_loaded_policies = local.use_loaded_policies
    use_custom_policies = local.use_custom_policies
    has_inline_policy   = local.has_inline_policy
    policy_arns_count   = length(local.additional_policy_arns)
  }
}
