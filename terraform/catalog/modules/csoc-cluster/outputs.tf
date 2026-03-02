################################################################################
# Outputs — forwarded from both child modules
################################################################################

# ─── AWS CSOC Outputs ─────────────────────────────────────────────────────────

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.aws_csoc.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.aws_csoc.cluster_endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA data"
  value       = module.aws_csoc.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  value       = module.aws_csoc.cluster_oidc_issuer_url
}

output "csoc_account_id" {
  description = "CSOC AWS account ID"
  value       = module.aws_csoc.csoc_account_id
}

output "spoke_account_ids" {
  description = "Spoke AWS account IDs"
  value       = module.aws_csoc.spoke_account_ids
}

output "ack_csoc_role_arn" {
  description = "ARN of the shared ACK CSOC source role"
  value       = module.aws_csoc.ack_csoc_role_arn
}

output "argocd_cluster_annotations_base" {
  description = "Base ArgoCD cluster secret annotations"
  value       = module.aws_csoc.argocd_cluster_annotations_base
}

output "argocd_cluster_labels_base" {
  description = "Base ArgoCD cluster secret labels"
  value       = module.aws_csoc.argocd_cluster_labels_base
}

# ─── ArgoCD Bootstrap Outputs ────────────────────────────────────────────────

output "git_repository_secret_names" {
  description = "Map of logical repo name to ArgoCD repository K8s secret name"
  value       = module.argocd_bootstrap.git_repository_secret_names
}

output "argocd_cluster_secret_name" {
  description = "Name of the ArgoCD cluster secret"
  value       = module.argocd_bootstrap.argocd_cluster_secret_name
}

output "bootstrap_applicationset_name" {
  description = "Name of the bootstrap ApplicationSet"
  value       = module.argocd_bootstrap.bootstrap_applicationset_name
}

output "connect_script_path" {
  description = "Path to the generated connect-csoc.sh script"
  value       = module.argocd_bootstrap.connect_script_path
}
