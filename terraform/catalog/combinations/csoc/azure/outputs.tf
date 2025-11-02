###############################################################################
# Resource Group Outputs
###############################################################################
output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.resource_group.resource_group_name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = module.resource_group.resource_group_id
}

###############################################################################
# VNet Outputs
###############################################################################
output "vpc_id" {
  description = "The ID of the VNet"
  value       = var.enable_vpc ? module.vnet.vnet_id : var.existing_vpc_id
}

output "vpc_name" {
  description = "The name of the VNet"
  value       = var.enable_vpc ? module.vnet.vnet_name : null
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = var.enable_vpc ? module.vnet.subnet_ids : var.existing_subnet_ids
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = []
}

###############################################################################
# AKS Cluster Outputs
###############################################################################
output "cluster_name" {
  description = "The name of the AKS cluster"
  value       = var.enable_k8s_cluster ? module.aks_cluster.cluster_name : null
}

output "cluster_id" {
  description = "The ID of the AKS cluster"
  value       = var.enable_k8s_cluster ? module.aks_cluster.cluster_id : null
}

output "cluster_endpoint" {
  description = "Endpoint for the AKS cluster API server"
  value       = var.enable_k8s_cluster ? module.aks_cluster.cluster_endpoint : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = var.enable_k8s_cluster ? module.aks_cluster.cluster_version : null
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL for workload identity"
  value       = var.enable_k8s_cluster ? module.aks_cluster.oidc_issuer_url : null
}

###############################################################################
# Managed Identity Outputs
###############################################################################
output "managed_identities" {
  description = "Map of managed identity details"
  value = {
    for k, v in module.managed_identities : k => {
      identity_id   = v.identity_id
      client_id     = v.client_id
      principal_id  = v.principal_id
      identity_name = v.identity_name
      service_name  = k
    }
  }
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
# ArgoCD Outputs
###############################################################################
output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = var.enable_argocd ? var.argocd_namespace : null
}

output "argocd_installed" {
  description = "Whether ArgoCD was installed"
  value       = var.enable_argocd && var.argocd_install
}

###############################################################################
# CSOC ConfigMap Outputs
###############################################################################
output "csoc_configmap_name" {
  description = "Name of the CSOC ConfigMap"
  value       = try(module.csoc_configmap.config_map_name, "")
}

output "csoc_configmap_namespace" {
  description = "Namespace of the CSOC ConfigMap"
  value       = try(module.csoc_configmap.config_map_namespace, "")
}

###############################################################################
# Metadata Outputs
###############################################################################
output "location" {
  description = "Azure region where resources are deployed"
  value       = var.location
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

