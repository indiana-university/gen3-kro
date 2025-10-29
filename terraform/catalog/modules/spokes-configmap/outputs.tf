output "config_map_name" {
  description = "Name of the ArgoCD cluster configuration ConfigMap"
  value       = var.create && var.cluster_info != null ? kubernetes_config_map_v1.argocd_cluster_config[0].metadata[0].name : null
}

output "config_map_namespace" {
  description = "Namespace of the ArgoCD cluster configuration ConfigMap"
  value       = var.create && var.cluster_info != null ? kubernetes_config_map_v1.argocd_cluster_config[0].metadata[0].namespace : null
}

output "addons" {
  description = "Addons configuration"
  value       = local.addons_map
}
