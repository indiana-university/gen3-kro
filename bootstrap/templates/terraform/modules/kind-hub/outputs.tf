output "endpoint" {
  description = "API endpoint for the Kind cluster."
  value       = try(kind_cluster.default[0].endpoint, null)
}

output "kubeconfig" {
  description = "Kubeconfig file for the Kind cluster."
  value       = try(kind_cluster.default[0].kubeconfig, null)
  sensitive   = true
}

output "credentials" {
  description = "Credentials for authenticating with the Kind cluster."
  value = try({
    client_certificate     = kind_cluster.default[0].client_certificate
    client_key             = kind_cluster.default[0].client_key
    cluster_ca_certificate = kind_cluster.default[0].cluster_ca_certificate
  }, null)
  sensitive = true
}