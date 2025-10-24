output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = module.gke_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = module.gke_cluster.endpoint
}

output "workload_identities" {
  description = "Workload identity service accounts"
  value = {
    for k, v in module.workload_identities : k => {
      email = v.service_account_email
    }
  }
}
