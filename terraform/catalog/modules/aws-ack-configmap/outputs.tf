output "configmap_name" {
  description = "Name of the created ConfigMap"
  value       = var.create && length(kubernetes_config_map_v1.ack_controller_role_map) > 0 ? kubernetes_config_map_v1.ack_controller_role_map[0].metadata[0].name : null
}

output "configmap_namespace" {
  description = "Namespace where ConfigMap is created"
  value       = var.configmap_namespace
}

output "controller_name" {
  description = "ACK controller name"
  value       = var.controller_name
}

output "account_role_mappings" {
  description = "Map of account IDs to role ARNs"
  value       = var.create && length(kubernetes_config_map_v1.ack_controller_role_map) > 0 ? kubernetes_config_map_v1.ack_controller_role_map[0].data : {}
}

