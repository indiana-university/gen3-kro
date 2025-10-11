output "argo_metadata_yaml" {
  description = "Argo metadata annotations used by the cluster (YAML)"
  value       = yamlencode(local.addons_metadata)
}

output "ack_controllers_flat_annotations" {
  description = "ACK controllers metadata (flattened annotations)"
  value = {
    for k, v in local.addons_metadata :
    k => v if startswith(k, "ack_")
  }
}
