# Output cluster name
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

# Output cluster endpoint
output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

# Output cluster CA certificate
output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# Output OIDC issuer URL
output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

# Account IDs
output "csoc_account_id" {
  description = "CSOC AWS account ID (retrieved dynamically from profile)"
  value       = local.csoc_account_id
}

output "spoke_account_ids" {
  description = "Spoke AWS account IDs (retrieved dynamically from profiles)"
  value       = local.spoke_account_ids
}

output "spoke_dns_config" {
  description = "Spoke DNS config (hosted zone ID + name per spoke)"
  value       = local.spoke_dns_config
}

# AWS Profile
output "aws_profile" {
  description = "AWS profile used for CSOC cluster"
  value       = var.aws_profile
}

# ACK CSOC source role outputs (shared across modes)
output "ack_csoc_role_arn" {
  description = "ARN of the shared ACK CSOC source role"
  value       = try(aws_iam_role.ack_csoc_source[0].arn, null)
}

output "ack_csoc_role_name" {
  description = "Name of the shared ACK CSOC source role"
  value       = try(aws_iam_role.ack_csoc_source[0].name, null)
}

output "argocd_namespace" {
  description = "ArgoCD namespace name (carries implicit dependency on namespace creation and ArgoCD install)"
  value = try(
    helm_release.argocd[0].namespace,                    # wait for ArgoCD Helm install
    kubernetes_namespace_v1.argocd[0].metadata[0].name,  # wait for namespace creation
    var.argocd_namespace                                 # fallback to variable
  )
}

output "argocd_cluster_annotations_base" {
  description = "Base ArgoCD cluster secret annotations derived from CSOC metadata"
  value       = local.addons_metadata
}

output "argocd_cluster_labels_base" {
  description = "Base ArgoCD cluster secret labels derived from CSOC addon flags"
  value       = local.addons
}
