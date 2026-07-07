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
  description = "ArgoCD namespace name expected by downstream in-cluster bootstrap"
  value       = var.argocd_namespace
}

output "argocd_self_managed_role_arn" {
  description = "ARN of the self-managed Argo CD IAM role"
  value       = try(aws_iam_role.argocd_self_managed[0].arn, null)
}

output "argocd_self_managed_role_name" {
  description = "Name of the self-managed Argo CD IAM role"
  value       = try(aws_iam_role.argocd_self_managed[0].name, null)
}

output "argocd_cluster_annotations_base" {
  description = "Base ArgoCD cluster secret annotations derived from CSOC metadata"
  value       = local.addons_metadata
}

output "argocd_cluster_labels_base" {
  description = "Base ArgoCD cluster secret labels derived from CSOC addon flags"
  value       = local.addons
}

output "foundation_ready_token" {
  description = "Opaque dependency token for downstream bootstrap ordering"
  value = join(",", compact([
    module.eks.cluster_name,
    try(aws_iam_role.ack_csoc_source[0].arn, null),
    try(aws_iam_role.argocd_self_managed[0].arn, null),
    try(aws_iam_role.argocd_controller[0].arn, null),
    try(aws_eks_capability.argocd[0].id, null),
    try(aws_eks_capability.ack[0].id, null),
    try(aws_eks_capability.kro[0].id, null)
  ]))
}
