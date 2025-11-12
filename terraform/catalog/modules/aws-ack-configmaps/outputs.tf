output "configmap_names" {
  description = "Map of controller names to their ConfigMap names"
  value = {
    for controller_name, cm in kubernetes_config_map_v1.ack_controller_cross_account_role_configmap :
    controller_name => cm.metadata[0].name
  }
}

output "configmap_namespaces" {
  description = "Map of controller names to their ConfigMap namespaces"
  value = {
    for controller_name, cm in kubernetes_config_map_v1.ack_controller_cross_account_role_configmap :
    controller_name => cm.metadata[0].namespace
  }
}

output "controllers_configured" {
  description = "List of controllers with ConfigMaps created"
  value       = keys(kubernetes_config_map_v1.ack_controller_cross_account_role_configmap)
}
