variable "create" {
  description = "Whether to create pod identity resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

###################################################################################################################################################
# EBS CSI Variables
###################################################################################################################################################
variable "enable_aws_ebs_csi" {
  description = "Enable AWS EBS CSI driver pod identity"
  type        = bool
  default     = false
}

variable "ebs_csi_kms_arns" {
  description = "KMS key ARNs for EBS CSI driver"
  type        = list(string)
  default     = ["arn:aws:kms:*:*:key/*"]
}

variable "ebs_csi_namespace" {
  description = "Kubernetes namespace for EBS CSI driver"
  type        = string
  default     = "kube-system"
}

variable "ebs_csi_service_account" {
  description = "Kubernetes service account for EBS CSI driver"
  type        = string
  default     = "ebs-csi-controller-sa"
}

###################################################################################################################################################
# External Secrets Variables
###################################################################################################################################################
variable "enable_external_secrets" {
  description = "Enable External Secrets pod identity"
  type        = bool
  default     = false
}

variable "external_secrets_kms_key_arns" {
  description = "KMS key ARNs for External Secrets"
  type        = list(string)
  default     = []
}

variable "external_secrets_secrets_manager_arns" {
  description = "Secrets Manager ARNs for External Secrets"
  type        = list(string)
  default     = []
}

variable "external_secrets_ssm_parameter_arns" {
  description = "SSM Parameter ARNs for External Secrets"
  type        = list(string)
  default     = []
}

variable "external_secrets_create_permission" {
  description = "Allow External Secrets to create secrets"
  type        = bool
  default     = false
}

variable "external_secrets_attach_custom_policy" {
  description = "Attach custom policy to External Secrets role"
  type        = bool
  default     = false
}

variable "external_secrets_policy_statements" {
  description = "Custom policy statements for External Secrets"
  type        = any
  default     = []
}

variable "external_secrets_namespace" {
  description = "Kubernetes namespace for External Secrets"
  type        = string
  default     = "external-secrets"
}

variable "external_secrets_service_account" {
  description = "Kubernetes service account for External Secrets"
  type        = string
  default     = "external-secrets"
}

###################################################################################################################################################
# AWS Load Balancer Controller Variables
###################################################################################################################################################
variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller pod identity"
  type        = bool
  default     = false
}

variable "aws_load_balancer_controller_namespace" {
  description = "Kubernetes namespace for AWS Load Balancer Controller"
  type        = string
  default     = "kube-system"
}

variable "aws_load_balancer_controller_service_account" {
  description = "Kubernetes service account for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

###################################################################################################################################################
# ArgoCD Variables
###################################################################################################################################################
variable "enable_argocd" {
  description = "Enable ArgoCD pod identity"
  type        = bool
  default     = false
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

###################################################################################################################################################
# Amazon Managed Service for Prometheus Variables
###################################################################################################################################################
variable "enable_amazon_managed_service_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus pod identity"
  type        = bool
  default     = false
}

variable "amazon_managed_service_prometheus_workspace_arns" {
  description = "Amazon Managed Service for Prometheus workspace ARNs"
  type        = list(string)
  default     = []
}

variable "amazon_managed_service_prometheus_namespace" {
  description = "Kubernetes namespace for Amazon Managed Service for Prometheus"
  type        = string
  default     = "prometheus"
}

variable "amazon_managed_service_prometheus_service_account" {
  description = "Kubernetes service account for Amazon Managed Service for Prometheus"
  type        = string
  default     = "amp-sa"
}

###################################################################################################################################################
# AWS AppMesh Controller Variables
###################################################################################################################################################
variable "enable_aws_appmesh_controller" {
  description = "Enable AWS AppMesh Controller pod identity"
  type        = bool
  default     = false
}

variable "aws_appmesh_controller_namespace" {
  description = "Kubernetes namespace for AWS AppMesh Controller"
  type        = string
  default     = "appmesh-system"
}

variable "aws_appmesh_controller_service_account" {
  description = "Kubernetes service account for AWS AppMesh Controller"
  type        = string
  default     = "appmesh-controller"
}

###################################################################################################################################################
# AWS AppMesh Envoy Proxy Variables
###################################################################################################################################################
variable "enable_aws_appmesh_envoy_proxy" {
  description = "Enable AWS AppMesh Envoy Proxy pod identity"
  type        = bool
  default     = false
}

variable "aws_appmesh_envoy_proxy_namespace" {
  description = "Kubernetes namespace for AWS AppMesh Envoy Proxy"
  type        = string
  default     = "appmesh-system"
}

variable "aws_appmesh_envoy_proxy_service_account" {
  description = "Kubernetes service account for AWS AppMesh Envoy Proxy"
  type        = string
  default     = "appmesh-envoy-proxy"
}

###################################################################################################################################################
# AWS CloudWatch Observability Variables
###################################################################################################################################################
variable "enable_aws_cloudwatch_observability" {
  description = "Enable AWS CloudWatch Observability pod identity"
  type        = bool
  default     = false
}

variable "aws_cloudwatch_observability_namespace" {
  description = "Kubernetes namespace for AWS CloudWatch Observability"
  type        = string
  default     = "amazon-cloudwatch"
}

variable "aws_cloudwatch_observability_service_account" {
  description = "Kubernetes service account for AWS CloudWatch Observability"
  type        = string
  default     = "cloudwatch-agent"
}

###################################################################################################################################################
# AWS EFS CSI Variables
###################################################################################################################################################
variable "enable_aws_efs_csi" {
  description = "Enable AWS EFS CSI driver pod identity"
  type        = bool
  default     = false
}

variable "aws_efs_csi_namespace" {
  description = "Kubernetes namespace for AWS EFS CSI driver"
  type        = string
  default     = "kube-system"
}

variable "aws_efs_csi_service_account" {
  description = "Kubernetes service account for AWS EFS CSI driver"
  type        = string
  default     = "efs-csi-controller-sa"
}

###################################################################################################################################################
# AWS FSx for Lustre CSI Variables
###################################################################################################################################################
variable "enable_aws_fsx_lustre_csi" {
  description = "Enable AWS FSx for Lustre CSI driver pod identity"
  type        = bool
  default     = false
}

variable "aws_fsx_lustre_csi_service_role_arns" {
  description = "Service role ARNs for AWS FSx for Lustre CSI driver"
  type        = list(string)
  default     = ["arn:aws:iam::*:role/aws-service-role/s3.data-source.lustre.fsx.amazonaws.com/*"]
}

variable "aws_fsx_lustre_csi_namespace" {
  description = "Kubernetes namespace for AWS FSx for Lustre CSI driver"
  type        = string
  default     = "kube-system"
}

variable "aws_fsx_lustre_csi_service_account" {
  description = "Kubernetes service account for AWS FSx for Lustre CSI driver"
  type        = string
  default     = "fsx-csi-controller-sa"
}

###################################################################################################################################################
# AWS Gateway Controller Variables
###################################################################################################################################################
variable "enable_aws_gateway_controller" {
  description = "Enable AWS Gateway Controller pod identity"
  type        = bool
  default     = false
}

variable "aws_gateway_controller_namespace" {
  description = "Kubernetes namespace for AWS Gateway Controller"
  type        = string
  default     = "aws-application-networking-system"
}

variable "aws_gateway_controller_service_account" {
  description = "Kubernetes service account for AWS Gateway Controller"
  type        = string
  default     = "gateway-api-controller"
}

###################################################################################################################################################
# AWS Load Balancer Controller - Target Group Binding Only Variables
###################################################################################################################################################
variable "enable_aws_lb_controller_targetgroup_binding_only" {
  description = "Enable AWS Load Balancer Controller Target Group Binding Only pod identity"
  type        = bool
  default     = false
}

variable "aws_lb_controller_targetgroup_arns" {
  description = "Target Group ARNs for AWS Load Balancer Controller"
  type        = list(string)
  default     = []
}

variable "aws_lb_controller_targetgroup_binding_only_namespace" {
  description = "Kubernetes namespace for AWS Load Balancer Controller Target Group Binding Only"
  type        = string
  default     = "kube-system"
}

variable "aws_lb_controller_targetgroup_binding_only_service_account" {
  description = "Kubernetes service account for AWS Load Balancer Controller Target Group Binding Only"
  type        = string
  default     = "aws-load-balancer-controller-targetgroup-binding-only"
}

###################################################################################################################################################
# AWS Node Termination Handler Variables
###################################################################################################################################################
variable "enable_aws_node_termination_handler" {
  description = "Enable AWS Node Termination Handler pod identity"
  type        = bool
  default     = false
}

variable "aws_node_termination_handler_sqs_queue_arns" {
  description = "SQS Queue ARNs for AWS Node Termination Handler"
  type        = list(string)
  default     = []
}

variable "aws_node_termination_handler_namespace" {
  description = "Kubernetes namespace for AWS Node Termination Handler"
  type        = string
  default     = "kube-system"
}

variable "aws_node_termination_handler_service_account" {
  description = "Kubernetes service account for AWS Node Termination Handler"
  type        = string
  default     = "aws-node-termination-handler"
}

###################################################################################################################################################
# AWS Private CA Issuer Variables
###################################################################################################################################################
variable "enable_aws_privateca_issuer" {
  description = "Enable AWS Private CA Issuer pod identity"
  type        = bool
  default     = false
}

variable "aws_privateca_issuer_acmca_arns" {
  description = "ACM PCA ARNs for AWS Private CA Issuer"
  type        = list(string)
  default     = []
}

variable "aws_privateca_issuer_namespace" {
  description = "Kubernetes namespace for AWS Private CA Issuer"
  type        = string
  default     = "cert-manager"
}

variable "aws_privateca_issuer_service_account" {
  description = "Kubernetes service account for AWS Private CA Issuer"
  type        = string
  default     = "aws-privateca-issuer"
}

###################################################################################################################################################
# AWS VPC CNI - IPv4 Variables
###################################################################################################################################################
variable "enable_aws_vpc_cni_ipv4" {
  description = "Enable AWS VPC CNI IPv4 pod identity"
  type        = bool
  default     = false
}

variable "aws_vpc_cni_ipv4_namespace" {
  description = "Kubernetes namespace for AWS VPC CNI IPv4"
  type        = string
  default     = "kube-system"
}

variable "aws_vpc_cni_ipv4_service_account" {
  description = "Kubernetes service account for AWS VPC CNI IPv4"
  type        = string
  default     = "aws-node"
}

###################################################################################################################################################
# AWS VPC CNI - IPv6 Variables
###################################################################################################################################################
variable "enable_aws_vpc_cni_ipv6" {
  description = "Enable AWS VPC CNI IPv6 pod identity"
  type        = bool
  default     = false
}

variable "aws_vpc_cni_ipv6_namespace" {
  description = "Kubernetes namespace for AWS VPC CNI IPv6"
  type        = string
  default     = "kube-system"
}

variable "aws_vpc_cni_ipv6_service_account" {
  description = "Kubernetes service account for AWS VPC CNI IPv6"
  type        = string
  default     = "aws-node"
}

###################################################################################################################################################
# Cert Manager Variables
###################################################################################################################################################
variable "enable_cert_manager" {
  description = "Enable Cert Manager pod identity"
  type        = bool
  default     = false
}

variable "cert_manager_hosted_zone_arns" {
  description = "Route53 Hosted Zone ARNs for Cert Manager"
  type        = list(string)
  default     = []
}

variable "cert_manager_namespace" {
  description = "Kubernetes namespace for Cert Manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_service_account" {
  description = "Kubernetes service account for Cert Manager"
  type        = string
  default     = "cert-manager"
}

###################################################################################################################################################
# Cluster Autoscaler Variables
###################################################################################################################################################
variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler pod identity"
  type        = bool
  default     = false
}

variable "cluster_autoscaler_cluster_names" {
  description = "EKS Cluster names for Cluster Autoscaler"
  type        = list(string)
  default     = []
}

variable "cluster_autoscaler_namespace" {
  description = "Kubernetes namespace for Cluster Autoscaler"
  type        = string
  default     = "kube-system"
}

variable "cluster_autoscaler_service_account" {
  description = "Kubernetes service account for Cluster Autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}

###################################################################################################################################################
# External DNS Variables
###################################################################################################################################################
variable "enable_external_dns" {
  description = "Enable External DNS pod identity"
  type        = bool
  default     = false
}

variable "external_dns_hosted_zone_arns" {
  description = "Route53 Hosted Zone ARNs for External DNS"
  type        = list(string)
  default     = []
}

variable "external_dns_namespace" {
  description = "Kubernetes namespace for External DNS"
  type        = string
  default     = "external-dns"
}

variable "external_dns_service_account" {
  description = "Kubernetes service account for External DNS"
  type        = string
  default     = "external-dns"
}

###################################################################################################################################################
# Mountpoint S3 CSI Variables
###################################################################################################################################################
variable "enable_mountpoint_s3_csi" {
  description = "Enable Mountpoint S3 CSI driver pod identity"
  type        = bool
  default     = false
}

variable "mountpoint_s3_csi_bucket_arns" {
  description = "S3 Bucket ARNs for Mountpoint S3 CSI driver"
  type        = list(string)
  default     = []
}

variable "mountpoint_s3_csi_bucket_path_arns" {
  description = "S3 Bucket Path ARNs for Mountpoint S3 CSI driver"
  type        = list(string)
  default     = []
}

variable "mountpoint_s3_csi_namespace" {
  description = "Kubernetes namespace for Mountpoint S3 CSI driver"
  type        = string
  default     = "kube-system"
}

variable "mountpoint_s3_csi_service_account" {
  description = "Kubernetes service account for Mountpoint S3 CSI driver"
  type        = string
  default     = "s3-csi-driver-sa"
}

###################################################################################################################################################
# Velero Variables
###################################################################################################################################################
variable "enable_velero" {
  description = "Enable Velero pod identity"
  type        = bool
  default     = false
}

variable "velero_s3_bucket_arns" {
  description = "S3 Bucket ARNs for Velero"
  type        = list(string)
  default     = []
}

variable "velero_s3_bucket_path_arns" {
  description = "S3 Bucket Path ARNs for Velero"
  type        = list(string)
  default     = []
}

variable "velero_namespace" {
  description = "Kubernetes namespace for Velero"
  type        = string
  default     = "velero"
}

variable "velero_service_account" {
  description = "Kubernetes service account for Velero"
  type        = string
  default     = "velero"
}
