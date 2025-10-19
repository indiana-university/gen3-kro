###############################################################################
# VPC Outputs
###############################################################################
output "vpc_id" {
  description = "The ID of the VPC"
  value       = var.enable_vpc ? module.vpc.vpc_id : var.existing_vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = var.enable_vpc ? module.vpc.vpc_cidr : null
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = var.enable_vpc ? module.vpc.private_subnets : var.existing_subnet_ids
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = var.enable_vpc ? module.vpc.public_subnets : []
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = var.enable_vpc ? module.vpc.vpc_arn : null
}

###############################################################################
# EKS Cluster Outputs
###############################################################################
output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_name : null
}

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_id : null
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_arn : null
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_endpoint : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_version : null
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_security_group_id : null
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.cluster_certificate_authority_data : null
  sensitive   = true
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = var.enable_eks_cluster ? module.eks_cluster.oidc_provider : null
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for the EKS cluster"
  value       = var.enable_eks_cluster ? module.eks_cluster.oidc_provider_arn : null
}

###############################################################################
# ACK IAM Policy Outputs
###############################################################################
output "ack_iam_policies" {
  description = "Map of ACK IAM policy details"
  value = var.enable_ack ? {
    for k, v in module.pod_identities :
    replace(k, "ack-", "") => {
      service_type  = v.service_type
      service_name  = v.service_name
      policy_source = v.policy_source
      policy_arn    = v.policy_arn
      role_arn      = v.role_arn
    }
    if startswith(k, "ack-")
  } : {}
}

###############################################################################
# ACK Pod Identity Outputs
###############################################################################
output "ack_pod_identities" {
  description = "Map of ACK pod identity details"
  value = var.enable_ack && var.enable_eks_cluster ? {
    for k, v in module.pod_identities :
    replace(k, "ack-", "") => {
      role_arn  = v.role_arn
      role_name = v.role_name
    }
    if startswith(k, "ack-")
  } : {}
}

output "ack_debug_iam_paths" {
  description = "Debug: IAM policy paths for ACK controllers"
  value = var.enable_ack && var.enable_eks_cluster ? {
    for k, v in module.pod_identities :
    replace(k, "ack-", "") => v.debug_iam_policy_paths
    if startswith(k, "ack-")
  } : {}
}

###############################################################################
# ACK Spoke Role Outputs
###############################################################################

###############################################################################
# Cross Account Policy Outputs
###############################################################################
output "cross_account_policies" {
  description = "Map of cross-account policy details"
  value = {
    for k, v in module.cross_account_policy : k => {
      policy_id   = v.policy_id
      policy_name = v.policy_name
    }
  }
}

###############################################################################
# Addons Pod Identities Outputs
###############################################################################
output "ebs_csi_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = try(module.pod_identities["addon-ebs_csi"].role_arn, null)
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets IAM role"
  value       = try(module.pod_identities["addon-external_secrets"].role_arn, null)
}

output "addons_pod_identity_roles" {
  description = "Map of addon pod identity IAM role ARNs keyed by addon"
  value = {
    for k, v in module.pod_identities :
    replace(k, "addon-", "") => v.role_arn
    if startswith(k, "addon-")
  }
}

###############################################################################
# ArgoCD Pod Identity Outputs
###############################################################################
output "argocd_pod_identity_role_arn" {
  description = "ARN of the IAM role associated with ArgoCD pod identity"
  value       = var.enable_argocd && var.enable_eks_cluster ? try(module.pod_identities["argocd-app-controller"].role_arn, null) : null
}

output "argocd_pod_identity_role_name" {
  description = "Name of the IAM role associated with ArgoCD pod identity"
  value       = var.enable_argocd && var.enable_eks_cluster ? try(module.pod_identities["argocd-app-controller"].role_name, null) : null
}

output "argocd_pod_identity_associations" {
  description = "Map of ArgoCD pod identity associations"
  value       = var.enable_argocd && var.enable_eks_cluster ? try(module.pod_identities["argocd-app-controller"].associations, {}) : {}
}

###############################################################################
# ArgoCD Outputs
###############################################################################
output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = var.enable_argocd ? try(module.argocd.argocd[0].namespace, null) : null
}

output "argocd_release_name" {
  description = "Helm release name for ArgoCD"
  value       = var.enable_argocd ? try(module.argocd.argocd[0].name, null) : null
}

output "argocd_cluster_secret" {
  description = "ArgoCD cluster secret metadata for the deployed cluster registration"
  value       = var.enable_argocd ? module.argocd.cluster : null
  sensitive   = true
}

output "argocd_applications" {
  description = "ArgoCD application resources rendered by the bootstrap chart"
  value       = var.enable_argocd ? module.argocd.apps : {}
}

###############################################################################
# Debug Outputs
###############################################################################
output "iam_git_config" {
  description = "IAM Git configuration for debugging"
  value = {
    iam_git_repo_url = var.iam_git_repo_url
    iam_git_branch   = var.iam_git_branch
    iam_base_path    = var.iam_base_path
  }
}
