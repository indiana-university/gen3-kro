# terraform/live/terragrunt.hcl
# Main infrastructure stack configuration

# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Local variables
locals {
  repo_root = get_repo_root()
}

# Point to the root module (catalog)
terraform {
  source = "${get_repo_root()}/terraform/modules/root"

  # Map module sources for local development
  # This allows Terragrunt to rewrite relative module paths
  extra_arguments "enable_source_map" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      TF_REGISTRY_DISCOVERY_RETRY = "5"
    }
  }

  # Copy sibling modules manually using before_hook
  before_hook "copy_modules" {
    commands     = ["init"]
    execute      = ["sh", "-c", "mkdir -p ../../modules && cp -r ${get_repo_root()}/terraform/modules/* ../../modules/ 2>/dev/null || true"]
    run_on_error = false
  }
}

# Direct inputs - no YAML parsing
inputs = {
  # AWS Configuration
  hub_aws_region = "us-east-1"
  aws_profile    = "boadeyem_tf"

  # Hub Cluster Configuration
  cluster_name       = "gen3-kro-hub"
  old_cluster_name   = ""  # Set to previous cluster name when performing migration
  vpc_name           = "gen3-kro-vpc"
  kubernetes_version = "1.33"
  hub_alias          = "gen3-csoc"

  # Paths
  outputs_dir    = "${get_repo_root()}/outputs"
  kubeconfig_dir = "~/.kube"

  # GitOps Configuration
  gitops_org_name        = "indiana-university"
  gitops_repo_name       = "gen3-kro"
  gitops_hub_repo_url    = "https://github.com/indiana-university/gen3-kro.git"
  gitops_rgds_repo_url   = "https://github.com/indiana-university/gen3-kro.git"
  gitops_spokes_repo_url = "https://github.com/indiana-university/gen3-kro.git"
  gitops_branch          = "jimi-container"
  gitops_bootstrap_path  = "argocd/bootstrap"
  gitops_rgds_path       = "argocd/shared"
  gitops_spokes_path     = "argocd/spokes"

  # ArgoCD Configuration
  enable_argo          = true
  argocd_chart_version = "8.6.0"

  # ACK Services to enable
  ack_services = [
    "cloudtrail",
    "cloudwatchlogs",
    "ec2",
    "efs",
    "eks",
    "iam",
    "kms",
    "opensearchservice",
    "rds",
    "route53",
    "s3",
    "secretsmanager",
    "sns",
    "sqs",
    "wafv2"
  ]

  # Addons Configuration
  addons = {
    enable_metrics_server          = true
    enable_kyverno                 = true
    enable_kyverno_policies        = true
    enable_kyverno_policy_reporter = true
    enable_argocd                  = true
    enable_cni_metrics_helper      = false
    enable_kube_state_metrics      = true
    enable_cert_manager            = false
    enable_external_dns            = false
    enable_external_secrets        = true
    enable_ack_iam                 = true
    enable_ack_eks                 = true
    enable_ack_ec2                 = true
    enable_ack_efs                 = true
    enable_kro                     = true
    enable_kro_eks_rgs             = true
    enable_multi_acct              = true
    enable_aws_efs_csi_driver      = false
    enable_aws_for_fluentbit       = false
    enable_cw_prometheus           = false
    enable_opentelemetry_operator  = false
    enable_prometheus_node_exporter = false
  }

  # Spoke Clusters Configuration
  spokes = [
    {
      alias      = "spoke1"
      region     = "us-east-1"
      profile    = "boadeyem_tf"
      account_id = ""
      tags = {
        Team    = "RDS"
        Purpose = "multi-account-demo"
      }
    }
  ]

  # Cross-account IAM
  enable_cross_account_iam = false

  # Additional tags
  tags = {
    Owner = "RDS"
  }
}
