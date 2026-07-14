output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "EKS OIDC issuer URL"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN created for the cluster"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "CSOC VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "CSOC private subnet IDs"
  value       = module.vpc.private_subnets
}

output "cluster_ready_token" {
  description = "Opaque value for downstream dependency ordering"
  value       = join(",", [module.eks.cluster_name, module.vpc.vpc_id])
}
