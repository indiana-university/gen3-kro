output "argo_metadata_yaml" {
  description = "Argo metadata annotations used by the cluster (YAML)"
  value       = yamlencode(local.addons_metadata)
}
