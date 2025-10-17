###################################################################################################################################################
# Individual Pod Identity Role ARN Outputs
###################################################################################################################################################

output "aws_ebs_csi_role_arn" {
  description = "IAM Role ARN for AWS EBS CSI driver"
  value       = var.create && contains(keys(local.enabled_addons), "ebs_csi") ? module.ebs_csi_pod_identity[0].iam_role_arn : null
}

output "aws_efs_csi_role_arn" {
  description = "IAM Role ARN for AWS EFS CSI driver"
  value       = var.create && contains(keys(local.enabled_addons), "efs_csi") ? module.aws_efs_csi_pod_identity[0].iam_role_arn : null
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = var.create && contains(keys(local.enabled_addons), "aws_load_balancer_controller") ? module.aws_load_balancer_controller_pod_identity[0].iam_role_arn : null
}

output "cert_manager_role_arn" {
  description = "IAM Role ARN for Cert Manager"
  value       = var.create && contains(keys(local.enabled_addons), "cert_manager") ? module.cert_manager_pod_identity[0].iam_role_arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "IAM Role ARN for Cluster Autoscaler"
  value       = var.create && contains(keys(local.enabled_addons), "cluster_autoscaler") ? module.cluster_autoscaler_pod_identity[0].iam_role_arn : null
}

output "external_dns_role_arn" {
  description = "IAM Role ARN for External DNS"
  value       = var.create && contains(keys(local.enabled_addons), "external_dns") ? module.external_dns_pod_identity[0].iam_role_arn : null
}

output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets"
  value       = var.create && contains(keys(local.enabled_addons), "external_secrets") ? module.external_secrets_pod_identity[0].iam_role_arn : null
}

###################################################################################################################################################
# Consolidated Output
###################################################################################################################################################

output "pod_identity_roles" {
  description = "All Pod Identity IAM Role ARNs"
  value = var.create ? {
    ebs_csi                      = contains(keys(local.enabled_addons), "ebs_csi") ? module.ebs_csi_pod_identity[0].iam_role_arn : null
    efs_csi                      = contains(keys(local.enabled_addons), "efs_csi") ? module.aws_efs_csi_pod_identity[0].iam_role_arn : null
    aws_load_balancer_controller = contains(keys(local.enabled_addons), "aws_load_balancer_controller") ? module.aws_load_balancer_controller_pod_identity[0].iam_role_arn : null
    cert_manager                 = contains(keys(local.enabled_addons), "cert_manager") ? module.cert_manager_pod_identity[0].iam_role_arn : null
    cluster_autoscaler           = contains(keys(local.enabled_addons), "cluster_autoscaler") ? module.cluster_autoscaler_pod_identity[0].iam_role_arn : null
    external_dns                 = contains(keys(local.enabled_addons), "external_dns") ? module.external_dns_pod_identity[0].iam_role_arn : null
    external_secrets             = contains(keys(local.enabled_addons), "external_secrets") ? module.external_secrets_pod_identity[0].iam_role_arn : null
  } : {}
}


