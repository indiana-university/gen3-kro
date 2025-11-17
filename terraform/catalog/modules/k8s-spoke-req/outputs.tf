################################################################################
# Namespace Outputs
################################################################################

output "spoke_namespaces" {
  description = "Map of spoke aliases to their namespace names"
  value = {
    for alias, ns in kubernetes_namespace_v1.spoke_infrastructure :
    alias => ns.metadata[0].name
  }
}

output "spoke_namespace_list" {
  description = "List of all spoke namespace names"
  value       = [for ns in kubernetes_namespace_v1.spoke_infrastructure : ns.metadata[0].name]
}

################################################################################
# ConfigMap Outputs
################################################################################

output "charter_configmap_name" {
  description = "Name of the spokes charter ConfigMap"
  value       = try(kubernetes_config_map_v1.spokes_charter[0].metadata[0].name, null)
}

output "charter_configmap_namespace" {
  description = "Namespace of the spokes charter ConfigMap"
  value       = try(kubernetes_config_map_v1.spokes_charter[0].metadata[0].namespace, null)
}

################################################################################
# Combined Outputs
################################################################################

output "enabled_spokes" {
  description = "List of enabled spoke aliases"
  value       = keys(kubernetes_namespace_v1.spoke_infrastructure)
}
