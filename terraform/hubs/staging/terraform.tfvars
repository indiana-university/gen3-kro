# Authentication and authorization
hub_aws_region      = "us-east-1"
account_ids         = "859011005590"
spoke_aws_region    = "us-east-1"
hub_aws_profile     = ""
spoke_aws_profile   = ""

# Cluster configuration
vpc_name           = "gen3-kro-staging-vpc"
kubernetes_version = "1.33"
cluster_name       = "gen3-kro-staging-hub"
enable_automode    = "true"
tenant             = "tenant1"
environment        = "staging"

#Cluster addons configuration
ackCreate             = "true"
use_ack               = "true"
enable_addon_selector = "true"
enable_efs            = "true"

addons                = {
  enable_metrics_server          = "true"
  enable_kyverno                 = "true"
  enable_kyverno_policies        = "true"
  enable_kyverno_policy_reporter = "true"
  enable_argocd                  = "true"
  enable_cni_metrics_helper      = "false"
  enable_kube_state_metrics      = "true"
  enable_cert_manager            = "false"
  enable_external_dns            = "false"
  enable_external_secrets        = "true"
  enable_ack_iam                 = "true"
  enable_ack_eks                 = "true"
  enable_ack_ec2                 = "true"
  enable_ack_efs                 = "true"
  enable_kro                     = "true"
  enable_kro_eks_rgs             = "true"
  enable_multi_acct              = "true"
}

# GitOps Addons configuration
gitops_addons_github_url               = "github.com"
gitops_addons_org_name                 = "indiana-university"
gitops_addons_app_id                   = ""
gitops_addons_app_installation_id      = ""
gitops_addons_app_private_key_ssm_path = "/gen3-kro-staging-hub/gen3-kro/private-key"
gitops_addons_repo_name                = "gen3-kro"
gitops_addons_repo_base_path           = "addons/"
gitops_addons_repo_path                = "bootstrap/default"
gitops_addons_repo_revision            = "main"

# GitOps Fleet configuration
gitops_fleet_github_url               = "github.com"
gitops_fleet_org_name                 = "indiana-university"
gitops_fleet_app_id                   = ""
gitops_fleet_app_installation_id      = ""
gitops_fleet_app_private_key_ssm_path = "/gen3-kro-staging-hub/gen3-kro/private-key"
gitops_fleet_repo_name                = "gen3-kro"
gitops_fleet_repo_base_path           = "fleet/"
gitops_fleet_repo_path                = "bootstrap/"
gitops_fleet_repo_revision            = "main"

# GitOps Platform configuration
gitops_platform_github_url               = "github.com"
gitops_platform_org_name                 = "indiana-university"
gitops_platform_app_id                   = ""
gitops_platform_app_installation_id      = ""
gitops_platform_app_private_key_ssm_path = "/gen3-kro-staging-hub/gen3-kro/private-key"
gitops_platform_repo_name                = "gen3-kro"
gitops_platform_repo_base_path           = "platform/"
gitops_platform_repo_path                = "bootstrap/"
gitops_platform_repo_revision            = "main"

# GitOps Workload configuration
gitops_workload_github_url               = "github.com"
gitops_workload_org_name                 = "indiana-university"
gitops_workload_app_id                   = ""
gitops_workload_app_installation_id      = ""
gitops_workload_app_private_key_ssm_path = "/gen3-kro-staging-hub/gen3-kro/private-key"
gitops_workload_repo_name                = "gen3-kro"
gitops_workload_repo_base_path           = "workloads/"
gitops_workload_repo_path                = "bootstrap/"
gitops_workload_repo_revision            = "main"

outputs_dir = "../../..//mnt/c/Users/boadeyem/OneDrive - Indiana University/Documents/Masters-Career Documents/Portfolio/Projects/gen3-kro/gen3-kro/automation/outputs/terraform"

tags = {
  hub_aws_profile = ""
  spoke_aws_profile = ""
}