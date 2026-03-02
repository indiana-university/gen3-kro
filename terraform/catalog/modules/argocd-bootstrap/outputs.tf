output "git_repository_secret_names" {
  description = "Map of logical repo name to ArgoCD repository K8s secret name"
  value = {
    for repo_key, secret in kubernetes_secret_v1.git_repository :
    repo_key => secret.metadata[0].name
  }
}

output "argocd_cluster_secret_name" {
  description = "Name of the ArgoCD cluster secret"
  value       = try(kubernetes_secret_v1.argocd_cluster[0].metadata[0].name, null)
}

output "spoke_account_ids" {
  description = "Spoke account IDs used for cluster annotations"
  value       = var.spoke_account_ids
}

output "cluster_annotations" {
  description = "Effective annotations set on the ArgoCD cluster secret"
  value       = local.cluster_secret_annotations
}

output "bootstrap_applicationset_name" {
  description = "Name of the bootstrap ApplicationSet managed by Terraform"
  value       = try(local.bootstrap_applicationset_manifest.metadata.name, null)
}

output "connect_script_path" {
  description = "Path to the generated connect-csoc.sh script"
  value       = try(local_file.connect_script[0].filename, null)
}
