# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the eks-pod-identities module
terraform {
  source = "../../modules//eks-pod-identities"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })

  # AWS region
  aws_region = get_env("AWS_REGION", "us-east-1")
}

# Dependencies
dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name = "mock-cluster"
    cluster_info = {
      cluster_name = "mock-cluster"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    cluster_name = dependency.eks_cluster.outputs.cluster_name

    # EBS CSI
    enable_aws_ebs_csi       = true
    ebs_csi_kms_arns         = ["arn:aws:kms:*:*:key/*"]
    ebs_csi_namespace        = "kube-system"
    ebs_csi_service_account  = "ebs-csi-controller-sa"

    # External Secrets
    enable_external_secrets                   = true
    external_secrets_kms_key_arns             = ["arn:aws:kms:${local.aws_region}:*:key/*"]
    external_secrets_secrets_manager_arns     = ["arn:aws:secretsmanager:${local.aws_region}:*:secret:*"]
    external_secrets_ssm_parameter_arns       = ["arn:aws:ssm:${local.aws_region}:*:parameter/*"]
    external_secrets_create_permission        = false
    external_secrets_attach_custom_policy     = false
    external_secrets_policy_statements        = []
    external_secrets_namespace                = "external-secrets"
    external_secrets_service_account          = "external-secrets"

    # AWS Load Balancer Controller
    enable_aws_load_balancer_controller                = true
    aws_load_balancer_controller_namespace             = "kube-system"
    aws_load_balancer_controller_service_account       = "aws-load-balancer-controller"

    # ArgoCD
    enable_argocd      = true
    argocd_namespace   = "argocd"

    # All other addons disabled by default (can be enabled as needed)
    enable_amazon_managed_service_prometheus = false
    enable_aws_appmesh_controller            = false
    enable_aws_appmesh_envoy_proxy           = false
    enable_aws_cloudwatch_observability      = false
    enable_aws_efs_csi                       = false
    enable_aws_fsx_lustre_csi                = false
    enable_aws_gateway_controller            = false
    enable_aws_lb_controller_targetgroup_binding_only = false
    enable_aws_node_termination_handler      = false
    enable_aws_privateca_issuer              = false
    enable_aws_vpc_cni_ipv4                  = false
    enable_aws_vpc_cni_ipv6                  = false
    enable_cert_manager                      = false
    enable_cluster_autoscaler                = false
    enable_external_dns                      = false
    enable_mountpoint_s3_csi                 = false
    enable_velero                            = false
  }
)
