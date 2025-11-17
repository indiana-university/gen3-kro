################################################################################
# Output Values
################################################################################

output "namespaces" {
  description = "Map of created controller namespaces"
  value = {
    for k, v in kubernetes_namespace_v1.controller :
    k => {
      name = v.metadata[0].name
      uid  = v.metadata[0].uid
    }
  }
}

output "service_accounts" {
  description = "Map of created controller service accounts"
  value = {
    for k, v in kubernetes_service_account_v1.controller :
    k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      uid       = v.metadata[0].uid
    }
  }
}

output "configmaps" {
  description = "Map of created controller configmaps"
  value = {
    for k, v in kubernetes_config_map_v1.controller_configmap :
    k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      uid       = v.metadata[0].uid
    }
  }
}
