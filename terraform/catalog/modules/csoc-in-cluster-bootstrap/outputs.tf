output "argocd_namespace" {
  description = "Argo CD namespace managed or targeted by this bootstrap module"
  value       = local.argocd_namespace_name
}

output "git_repository_secret_names" {
  description = "Map of logical repo name to Argo CD repository Kubernetes secret name"
  value       = module.argocd_bootstrap.git_repository_secret_names
}

output "argocd_cluster_secret_name" {
  description = "Name of the Argo CD cluster secret"
  value       = module.argocd_bootstrap.argocd_cluster_secret_name
}

output "spoke_account_ids" {
  description = "Spoke account IDs used for cluster annotations"
  value       = module.argocd_bootstrap.spoke_account_ids
}

output "cluster_annotations" {
  description = "Effective annotations set on the Argo CD cluster secret"
  value       = module.argocd_bootstrap.cluster_annotations
}

output "bootstrap_applicationset_name" {
  description = "Name of the bootstrap ApplicationSet managed by Terraform"
  value       = module.argocd_bootstrap.bootstrap_applicationset_name
}

output "connect_script_path" {
  description = "Path to the generated connect-csoc.sh script"
  value       = module.argocd_bootstrap.connect_script_path
}
