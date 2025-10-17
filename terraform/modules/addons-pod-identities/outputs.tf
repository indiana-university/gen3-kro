###################################################################################################################################################
# Individual Pod Identity Role ARN Outputs
###################################################################################################################################################

output "amazon_managed_service_prometheus_role_arn" {
  description = "IAM Role ARN for Amazon Managed Service for Prometheus"
  value       = var.create && var.enable_amazon_managed_service_prometheus ? module.amazon_managed_service_prometheus_pod_identity[0].iam_role_arn : null
}

output "argocd_hub_role_arn" {
  description = "IAM Role ARN for ArgoCD Hub"
  value       = var.create && var.enable_argocd ? module.argocd_hub_pod_identity[0].iam_role_arn : null
}

output "aws_appmesh_controller_role_arn" {
  description = "IAM Role ARN for AWS AppMesh Controller"
  value       = var.create && var.enable_aws_appmesh_controller ? module.aws_appmesh_controller_pod_identity[0].iam_role_arn : null
}

output "aws_appmesh_envoy_proxy_role_arn" {
  description = "IAM Role ARN for AWS AppMesh Envoy Proxy"
  value       = var.create && var.enable_aws_appmesh_envoy_proxy ? module.aws_appmesh_envoy_proxy_pod_identity[0].iam_role_arn : null
}

output "aws_cloudwatch_observability_role_arn" {
  description = "IAM Role ARN for AWS CloudWatch Observability"
  value       = var.create && var.enable_aws_cloudwatch_observability ? module.aws_cloudwatch_observability_pod_identity[0].iam_role_arn : null
}

output "aws_ebs_csi_role_arn" {
  description = "IAM Role ARN for AWS EBS CSI driver"
  value       = var.create && var.enable_aws_ebs_csi ? module.aws_ebs_csi_pod_identity[0].iam_role_arn : null
}

output "aws_efs_csi_role_arn" {
  description = "IAM Role ARN for AWS EFS CSI driver"
  value       = var.create && var.enable_aws_efs_csi ? module.aws_efs_csi_pod_identity[0].iam_role_arn : null
}

output "aws_fsx_lustre_csi_role_arn" {
  description = "IAM Role ARN for AWS FSx for Lustre CSI driver"
  value       = var.create && var.enable_aws_fsx_lustre_csi ? module.aws_fsx_lustre_csi_pod_identity[0].iam_role_arn : null
}

output "aws_gateway_controller_role_arn" {
  description = "IAM Role ARN for AWS Gateway Controller"
  value       = var.create && var.enable_aws_gateway_controller ? module.aws_gateway_controller_pod_identity[0].iam_role_arn : null
}

output "aws_lb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = var.create && var.enable_aws_load_balancer_controller ? module.aws_lb_controller_pod_identity[0].iam_role_arn : null
}

output "aws_lb_controller_targetgroup_binding_only_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller Target Group Binding Only"
  value       = var.create && var.enable_aws_lb_controller_targetgroup_binding_only ? module.aws_lb_controller_targetgroup_binding_only_pod_identity[0].iam_role_arn : null
}

output "aws_node_termination_handler_role_arn" {
  description = "IAM Role ARN for AWS Node Termination Handler"
  value       = var.create && var.enable_aws_node_termination_handler ? module.aws_node_termination_handler_pod_identity[0].iam_role_arn : null
}

output "aws_privateca_issuer_role_arn" {
  description = "IAM Role ARN for AWS Private CA Issuer"
  value       = var.create && var.enable_aws_privateca_issuer ? module.aws_privateca_issuer_pod_identity[0].iam_role_arn : null
}

output "aws_vpc_cni_ipv4_role_arn" {
  description = "IAM Role ARN for AWS VPC CNI IPv4"
  value       = var.create && var.enable_aws_vpc_cni_ipv4 ? module.aws_vpc_cni_ipv4_pod_identity[0].iam_role_arn : null
}

output "aws_vpc_cni_ipv6_role_arn" {
  description = "IAM Role ARN for AWS VPC CNI IPv6"
  value       = var.create && var.enable_aws_vpc_cni_ipv6 ? module.aws_vpc_cni_ipv6_pod_identity[0].iam_role_arn : null
}

output "cert_manager_role_arn" {
  description = "IAM Role ARN for Cert Manager"
  value       = var.create && var.enable_cert_manager ? module.cert_manager_pod_identity[0].iam_role_arn : null
}

output "cluster_autoscaler_role_arn" {
  description = "IAM Role ARN for Cluster Autoscaler"
  value       = var.create && var.enable_cluster_autoscaler ? module.cluster_autoscaler_pod_identity[0].iam_role_arn : null
}

output "external_dns_role_arn" {
  description = "IAM Role ARN for External DNS"
  value       = var.create && var.enable_external_dns ? module.external_dns_pod_identity[0].iam_role_arn : null
}

output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets"
  value       = var.create && var.enable_external_secrets ? module.external_secrets_pod_identity[0].iam_role_arn : null
}

output "mountpoint_s3_csi_role_arn" {
  description = "IAM Role ARN for Mountpoint S3 CSI driver"
  value       = var.create && var.enable_mountpoint_s3_csi ? module.mountpoint_s3_csi_pod_identity[0].iam_role_arn : null
}

output "velero_role_arn" {
  description = "IAM Role ARN for Velero"
  value       = var.create && var.enable_velero ? module.velero_pod_identity[0].iam_role_arn : null
}

###################################################################################################################################################
# Consolidated Output
###################################################################################################################################################

output "pod_identity_roles" {
  description = "All Pod Identity IAM Role ARNs"
  value = var.create ? {
    amazon_managed_service_prometheus          = var.enable_amazon_managed_service_prometheus ? module.amazon_managed_service_prometheus_pod_identity[0].iam_role_arn : null
    argocd_hub                                 = var.enable_argocd ? module.argocd_hub_pod_identity[0].iam_role_arn : null
    aws_appmesh_controller                     = var.enable_aws_appmesh_controller ? module.aws_appmesh_controller_pod_identity[0].iam_role_arn : null
    aws_appmesh_envoy_proxy                    = var.enable_aws_appmesh_envoy_proxy ? module.aws_appmesh_envoy_proxy_pod_identity[0].iam_role_arn : null
    aws_cloudwatch_observability               = var.enable_aws_cloudwatch_observability ? module.aws_cloudwatch_observability_pod_identity[0].iam_role_arn : null
    aws_ebs_csi                                = var.enable_aws_ebs_csi ? module.aws_ebs_csi_pod_identity[0].iam_role_arn : null
    aws_efs_csi                                = var.enable_aws_efs_csi ? module.aws_efs_csi_pod_identity[0].iam_role_arn : null
    aws_fsx_lustre_csi                         = var.enable_aws_fsx_lustre_csi ? module.aws_fsx_lustre_csi_pod_identity[0].iam_role_arn : null
    aws_gateway_controller                     = var.enable_aws_gateway_controller ? module.aws_gateway_controller_pod_identity[0].iam_role_arn : null
    aws_load_balancer_controller               = var.enable_aws_load_balancer_controller ? module.aws_lb_controller_pod_identity[0].iam_role_arn : null
    aws_lb_controller_targetgroup_binding_only = var.enable_aws_lb_controller_targetgroup_binding_only ? module.aws_lb_controller_targetgroup_binding_only_pod_identity[0].iam_role_arn : null
    aws_node_termination_handler               = var.enable_aws_node_termination_handler ? module.aws_node_termination_handler_pod_identity[0].iam_role_arn : null
    aws_privateca_issuer                       = var.enable_aws_privateca_issuer ? module.aws_privateca_issuer_pod_identity[0].iam_role_arn : null
    aws_vpc_cni_ipv4                           = var.enable_aws_vpc_cni_ipv4 ? module.aws_vpc_cni_ipv4_pod_identity[0].iam_role_arn : null
    aws_vpc_cni_ipv6                           = var.enable_aws_vpc_cni_ipv6 ? module.aws_vpc_cni_ipv6_pod_identity[0].iam_role_arn : null
    cert_manager                               = var.enable_cert_manager ? module.cert_manager_pod_identity[0].iam_role_arn : null
    cluster_autoscaler                         = var.enable_cluster_autoscaler ? module.cluster_autoscaler_pod_identity[0].iam_role_arn : null
    external_dns                               = var.enable_external_dns ? module.external_dns_pod_identity[0].iam_role_arn : null
    external_secrets                           = var.enable_external_secrets ? module.external_secrets_pod_identity[0].iam_role_arn : null
    mountpoint_s3_csi                          = var.enable_mountpoint_s3_csi ? module.mountpoint_s3_csi_pod_identity[0].iam_role_arn : null
    velero                                     = var.enable_velero ? module.velero_pod_identity[0].iam_role_arn : null
  } : {}
}

