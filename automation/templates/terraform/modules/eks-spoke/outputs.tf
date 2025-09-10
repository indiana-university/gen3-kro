output "cluster_info" {
  value = module.eks
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  value       = module.vpc.vpc_id
}

output "argocd_hub_pod_identity_iam_role_arn" {
  description = "IAM Role ARN for ArgoCD Hub Pod Identity"
  value       = module.argocd_hub_pod_identity.iam_role_arn
}

output "account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "policy_arn" {
  description = "Recommended policy ARNs"
  value       = data.http.policy_arn
}

output "azs" {
  description = "List of availability zones"
  value       = data.aws_availability_zones.available.names
}

output "private_keys" {
  description = "Private keys stored in SSM"
  value       = data.aws_ssm_parameter.private_keys
}