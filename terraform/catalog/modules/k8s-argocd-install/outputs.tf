output "argocd_namespace" {
  description = "Namespace containing Argo CD"
  value       = local.argocd_namespace_name
}

output "argocd_release_name" {
  description = "Name of the self-managed Argo CD Helm release"
  value       = try(helm_release.argocd[0].name, null)
}

output "install_ready_token" {
  description = "Opaque value for downstream dependency ordering"
  value = join(",", concat(
    kubernetes_namespace_v1.argocd[*].metadata[0].name,
    helm_release.argocd[*].name
  ))
}
