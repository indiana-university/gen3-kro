output "repo_secret_names" {
  description = "Names of the ExternalSecrets created for ArgoCD"
  value       = [for k, v in kubernetes_manifest.repo_secrets : v.manifest.metadata.name]
}
