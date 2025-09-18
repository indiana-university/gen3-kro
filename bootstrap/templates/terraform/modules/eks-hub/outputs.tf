output "cluster_info" {
  description = "EKS cluster information"
  value       = module.eks[0]
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  value       = module.vpc[0].vpc_id
}

output "argocd_hub_pod_identity_iam_role_arn" {
  description = "IAM Role ARN for ArgoCD Hub Pod Identity"
  value       = module.argocd_hub_pod_identity[0].iam_role_arn
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current[0].account_id
}

output "azs" {
  description = "List of availability zones"
  value       = data.aws_availability_zones.available[0].names
}