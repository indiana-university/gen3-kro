output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = var.create ? module.eks[0].cluster_name : null
}

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = var.create ? module.eks[0].cluster_id : null
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = var.create ? module.eks[0].cluster_arn : null
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = var.create ? module.eks[0].cluster_endpoint : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = var.create ? module.eks[0].cluster_version : null
}

output "cluster_platform_version" {
  description = "The platform version of the EKS cluster"
  value       = var.create ? try(module.eks[0].cluster_platform_version, "") : null
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = var.create ? try(module.eks[0].cluster_security_group_id, "") : null
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = var.create ? try(module.eks[0].cluster_certificate_authority_data, "") : null
  sensitive   = true
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = var.create ? try(module.eks[0].oidc_provider, "") : null
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for the EKS cluster"
  value       = var.create ? try(module.eks[0].oidc_provider_arn, "") : null
}

output "account_id" {
  description = "AWS Account ID"
  value       = var.create ? data.aws_caller_identity.current[0].account_id : null
}

output "region" {
  description = "AWS Region where the cluster is deployed"
  value       = var.region
}

output "cluster_info" {
  description = "Consolidated cluster information"
  value = var.create ? {
    cluster_name                  = module.eks[0].cluster_name
    cluster_id                    = module.eks[0].cluster_id
    cluster_arn                   = module.eks[0].cluster_arn
    cluster_endpoint              = module.eks[0].cluster_endpoint
    cluster_version               = module.eks[0].cluster_version
    cluster_platform_version      = try(module.eks[0].cluster_platform_version, "")
    cluster_security_group_id     = try(module.eks[0].cluster_security_group_id, "")
    cluster_certificate_authority = try(module.eks[0].cluster_certificate_authority_data, "")
    oidc_provider                 = try(module.eks[0].oidc_provider, "")
    oidc_provider_arn             = try(module.eks[0].oidc_provider_arn, "")
  } : null
}

