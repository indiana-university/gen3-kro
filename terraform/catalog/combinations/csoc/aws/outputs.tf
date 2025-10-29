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
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_name : null
}

output "cluster_id" {
  description = "The ID of the EKS cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_id : null
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_arn : null
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_endpoint : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_version : null
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_security_group_id : null
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.cluster_certificate_authority_data : null
  sensitive   = true
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = var.enable_k8s_cluster ? module.eks_cluster.oidc_provider : null
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for the EKS cluster"
  value       = var.enable_k8s_cluster ? module.eks_cluster.oidc_provider_arn : null
}


output "iam_policies_debug" {
  description = "Debug: IAM policies loaded status"
  value = {
    for k, v in module.iam_policies :
    k => {
      has_inline_policy = v.has_inline_policy
    }
  }
}

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
  value       = try(module.pod_identities["ebs_csi"].role_arn, null)
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets IAM role"
  value       = try(module.pod_identities["external_secrets"].role_arn, null)
}

output "addons_pod_identity_roles" {
  description = "Map of pod identity IAM role ARNs keyed by service/addon"
  value       = { for k, v in module.pod_identities : k => v.role_arn }
}

###############################################################################
# ArgoCD Pod Identity Outputs
###############################################################################
output "argocd_pod_identity_role_arn" {
  description = "ARN of the IAM role associated with ArgoCD pod identity"
  value       = var.enable_argocd && var.enable_k8s_cluster ? try(module.pod_identities["argocd"].role_arn, null) : null
}

output "argocd_pod_identity_role_name" {
  description = "Name of the IAM role associated with ArgoCD pod identity"
  value       = var.enable_argocd && var.enable_k8s_cluster ? try(module.pod_identities["argocd"].role_name, null) : null
}

output "argocd_pod_identity_associations" {
  description = "Map of ArgoCD pod identity associations"
  value       = var.enable_argocd && var.enable_k8s_cluster ? try(module.pod_identities["argocd"].associations, {}) : {}
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

output "argocd_hub_configmap_name" {
  description = "Name of the hub ConfigMap created for ArgoCD"
  value       = var.enable_argocd ? try(module.hub_configmap.config_map_name, "") : ""
}

output "argocd_hub_configmap_namespace" {
  description = "Namespace of the hub ConfigMap created for ArgoCD"
  value       = var.enable_argocd ? try(module.hub_configmap.config_map_namespace, "") : ""
}

output "argocd_cluster_secret" {
  description = "ArgoCD cluster secret metadata for the deployed cluster registration"
  value       = var.enable_argocd ? module.argocd.cluster : null
  sensitive   = true
}

output "argocd_applications" {
  description = "ArgoCD application resources rendered by the bootstrap chart"
  value       = var.enable_argocd ? module.argocd.apps : {}
  sensitive   = true
}

output "argocd_server_url" {
  description = "ArgoCD server access information"
  value = var.enable_argocd ? {
    service_name         = "argo-cd-argocd-server"
    namespace            = "argocd"
    port                 = 443
    port_forward_command = "kubectl port-forward -n argocd svc/argo-cd-argocd-server 8080:443"
    admin_user           = "admin"
    get_password_command = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  } : null
}

###############################################################################
# End of File
###############################################################################
