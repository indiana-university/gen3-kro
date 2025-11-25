output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = var.create ? google_container_cluster.this[0].name : null
}

output "cluster_id" {
  description = "ID of the GKE cluster"
  value       = var.create ? google_container_cluster.this[0].id : null
}

output "cluster_endpoint" {
  description = "Cluster endpoint for API server"
  value       = var.create ? google_container_cluster.this[0].endpoint : null
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = var.create ? google_container_cluster.this[0].master_auth[0].cluster_ca_certificate : null
  sensitive   = true
}

output "endpoint" {
  description = "Cluster endpoint (alias for cluster_endpoint)"
  value       = var.create ? google_container_cluster.this[0].endpoint : null
}

output "master_version" {
  description = "Kubernetes master version"
  value       = var.create ? google_container_cluster.this[0].master_version : null
}

output "workload_identity_pool" {
  description = "Workload identity pool"
  value       = var.create && var.workload_identity_enabled ? "${var.project_id}.svc.id.goog" : null
}

