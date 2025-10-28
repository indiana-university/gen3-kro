###############################################################################
# VPC Outputs
###############################################################################
output "vpc_id" {
  description = "The name of the VPC network"
  value       = var.enable_vpc ? module.vpc.network_name : var.existing_vpc_id
}

output "vpc_name" {
  description = "The name of the VPC network"
  value       = var.enable_vpc ? module.vpc.network_name : null
}

output "private_subnets" {
  description = "List of private subnet names"
  value       = var.enable_vpc ? module.vpc.subnet_names : var.existing_subnet_ids
}

output "public_subnets" {
  description = "List of public subnet names"
  value       = []
}

###############################################################################
# GKE Cluster Outputs
###############################################################################
output "cluster_name" {
  description = "The name of the GKE cluster"
  value       = var.enable_k8s_cluster ? module.gke_cluster.cluster_name : null
}

output "cluster_id" {
  description = "The ID of the GKE cluster"
  value       = var.enable_k8s_cluster ? module.gke_cluster.cluster_id : null
}

output "cluster_endpoint" {
  description = "Endpoint for the GKE cluster API server"
  value       = var.enable_k8s_cluster ? module.gke_cluster.cluster_endpoint : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = var.enable_k8s_cluster ? module.gke_cluster.cluster_version : null
}

###############################################################################
# Workload Identity Outputs
###############################################################################
output "workload_identities" {
  description = "Map of workload identity details"
  value = {
    for k, v in module.workload_identities : k => {
      service_account_email = v.service_account_email
      service_account_name  = v.service_account_name
      service_account_id    = v.service_account_id
      service_name          = k
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
# Hub ConfigMap Outputs
###############################################################################
output "hub_configmap_name" {
  description = "Name of the hub ConfigMap"
  value       = try(module.hub_configmap.config_map_name, "")
}

output "hub_configmap_namespace" {
  description = "Namespace of the hub ConfigMap"
  value       = try(module.hub_configmap.config_map_namespace, "")
}

###############################################################################
# Metadata Outputs
###############################################################################
output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

