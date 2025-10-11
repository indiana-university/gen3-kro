output "argo_metadata_yaml" {
  description = "Argo metadata annotations used by the cluster (YAML)"
  value       = yamlencode(local.addons_metadata)
}

output "ack_controllers_metadata" {
  description = "ACK controllers metadata (nested JSON per controller)"
  value       = local.addons_metadata["ack_controllers"]
}
