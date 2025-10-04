output "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  value       = var.create ? module.vpc[0].vpc_id : null
}

output "argocd_hub_pod_identity_iam_role_arn" {
  description = "IAM Role ARN for ArgoCD Hub Pod Identity"
  value       = (var.create && var.oss_addons.enable_argocd) ? module.argocd_hub_pod_identity[0].iam_role_arn : null
}

output "account_id" {
  description = "AWS Account ID"
  value       = var.create ? data.aws_caller_identity.current[0].account_id : null
}

output "azs" {
  description = "List of availability zones"
  value       = var.create ? data.aws_availability_zones.available[0].names : []
}

output "cluster_info" {
  description = "EKS cluster information"
  value       = var.create ? module.eks[0] : null
}
