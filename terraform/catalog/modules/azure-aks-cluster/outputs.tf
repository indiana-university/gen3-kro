output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.this[0].name : null
}

output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = var.create ? azurerm_kubernetes_cluster.this[0].id : null
}

output "kube_config" {
  description = "Kubernetes config for the cluster"
  value       = var.create ? azurerm_kubernetes_cluster.this[0].kube_config_raw : null
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity"
  value       = var.create ? azurerm_kubernetes_cluster.this[0].oidc_issuer_url : null
}

output "kubelet_identity" {
  description = "Kubelet identity details"
  value       = var.create ? azurerm_kubernetes_cluster.this[0].kubelet_identity : null
}
