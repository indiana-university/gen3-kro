# Authentication and authorization
hub_aws_region      = "$HUB_AWS_REGION"
account_ids         = "$HUB_ACCOUNT_ID"
spoke_aws_region    = "$SPOKE_AWS_REGION"
hub_aws_profile     = "$HUB_AWS_PROFILE"
spoke_aws_profile   = "$SPOKE_AWS_PROFILE"

# Cluster configuration
vpc_name           = "$HUB_VPC_NAME"
kubernetes_version = "$HUB_KUBERNETES_VERSION"
cluster_name       = "$HUB_CLUSTER_NAME"
enable_automode    = "$HUB_ENABLE_AUTOMODE"
tenant             = "$HUB_TENANT"
environment        = "$ENVIRONMENT"

#Cluster addons configuration
ackCreate             = "$HUB_ACK_CREATE"
use_ack               = "$HUB_USE_ACK"
enable_addon_selector = "$HUB_ENABLE_ADDON_SELECTOR"
enable_efs            = "$HUB_ENABLE_EFS"

addons                = {
  enable_metrics_server          = "$HUB_ADDONS_ENABLE_METRICS_SERVER"
  enable_kyverno                 = "$HUB_ADDONS_ENABLE_KYVERNO"
  enable_kyverno_policies        = "$HUB_ADDONS_ENABLE_KYVERNO_POLICIES"
  enable_kyverno_policy_reporter = "$HUB_ADDONS_ENABLE_KYVERNO_POLICY_REPORTER"
  enable_argocd                  = "$HUB_ADDONS_ENABLE_ARGOCD"
  enable_cni_metrics_helper      = "$HUB_ADDONS_ENABLE_CNI_METRICS_HELPER"
  enable_kube_state_metrics      = "$HUB_ADDONS_ENABLE_KUBE_STATE_METRICS"
  enable_cert_manager            = "$HUB_ADDONS_ENABLE_CERT_MANAGER"
  enable_external_dns            = "$HUB_ADDONS_ENABLE_EXTERNAL_DNS"
  enable_external_secrets        = "$HUB_ADDONS_ENABLE_EXTERNAL_SECRETS"
  enable_ack_iam                 = "$HUB_ADDONS_ENABLE_ACK_IAM"
  enable_ack_eks                 = "$HUB_ADDONS_ENABLE_ACK_EKS"
  enable_ack_ec2                 = "$HUB_ADDONS_ENABLE_ACK_EC2"
  enable_ack_efs                 = "$HUB_ADDONS_ENABLE_ACK_EFS"
  enable_kro                     = "$HUB_ADDONS_ENABLE_KRO"
  enable_kro_eks_rgs             = "$HUB_ADDONS_ENABLE_KRO_EKS_RGS"
  enable_multi_acct              = "$HUB_ADDONS_ENABLE_MULTI_ACCT"
}

# GitOps Addons configuration
gitops_addons_github_url               = "$GITOPS_ADDONS_GITHUB_URL"
gitops_addons_org_name                 = "$GITOPS_ADDONS_ORG_NAME"
gitops_addons_app_id                   = "$GITOPS_ADDONS_APP_ID"
gitops_addons_app_installation_id      = "$GITOPS_ADDONS_APP_INSTALLATION_ID"
gitops_addons_app_private_key_ssm_path = "$GITOPS_ADDONS_APP_PRIVATE_KEY_PATH"
gitops_addons_repo_name                = "$GITOPS_ADDONS_REPO_NAME"
gitops_addons_repo_base_path           = "$GITOPS_ADDONS_REPO_BASE_PATH"
gitops_addons_repo_path                = "$GITOPS_ADDONS_REPO_BOOTSTRAP_PATH"
gitops_addons_repo_revision            = "$GITOPS_ADDONS_REPO_REVISION"

# GitOps Fleet configuration
gitops_fleet_github_url               = "$GITOPS_FLEET_GITHUB_URL"
gitops_fleet_org_name                 = "$GITOPS_FLEET_ORG_NAME"
gitops_fleet_app_id                   = "$GITOPS_FLEET_APP_ID"
gitops_fleet_app_installation_id      = "$GITOPS_FLEET_APP_INSTALLATION_ID"
gitops_fleet_app_private_key_ssm_path = "$GITOPS_FLEET_APP_PRIVATE_KEY_PATH"
gitops_fleet_repo_name                = "$GITOPS_FLEET_REPO_NAME"
gitops_fleet_repo_base_path           = "$GITOPS_FLEET_REPO_BASE_PATH"
gitops_fleet_repo_path                = "$GITOPS_FLEET_REPO_BOOTSTRAP_PATH"
gitops_fleet_repo_revision            = "$GITOPS_FLEET_REPO_REVISION"

# GitOps Platform configuration
gitops_platform_github_url               = "$GITOPS_PLATFORM_GITHUB_URL"
gitops_platform_org_name                 = "$GITOPS_PLATFORM_ORG_NAME"
gitops_platform_app_id                   = "$GITOPS_PLATFORM_APP_ID"
gitops_platform_app_installation_id      = "$GITOPS_PLATFORM_APP_INSTALLATION_ID"
gitops_platform_app_private_key_ssm_path = "$GITOPS_PLATFORM_APP_PRIVATE_KEY_PATH"
gitops_platform_repo_name                = "$GITOPS_PLATFORM_REPO_NAME"
gitops_platform_repo_base_path           = "$GITOPS_PLATFORM_REPO_BASE_PATH"
gitops_platform_repo_path                = "$GITOPS_PLATFORM_REPO_BOOTSTRAP_PATH"
gitops_platform_repo_revision            = "$GITOPS_PLATFORM_REPO_REVISION"

# GitOps Workload configuration
gitops_workload_github_url               = "$GITOPS_WORKLOAD_GITHUB_URL"
gitops_workload_org_name                 = "$GITOPS_WORKLOAD_ORG_NAME"
gitops_workload_app_id                   = "$GITOPS_WORKLOAD_APP_ID"
gitops_workload_app_installation_id      = "$GITOPS_WORKLOAD_APP_INSTALLATION_ID"
gitops_workload_app_private_key_ssm_path = "$GITOPS_WORKLOAD_APP_PRIVATE_KEY_PATH"
gitops_workload_repo_name                = "$GITOPS_WORKLOAD_REPO_NAME"
gitops_workload_repo_base_path           = "$GITOPS_WORKLOAD_REPO_BASE_PATH"
gitops_workload_repo_path                = "$GITOPS_WORKLOAD_REPO_BOOTSTRAP_PATH"
gitops_workload_repo_revision            = "$GITOPS_WORKLOAD_REPO_REVISION"

outputs_dir = "$TERRAFORM_ENV_TO_OUTPUTS"

tags = {
  hub_aws_profile = "$HUB_AWS_PROFILE"
  spoke_aws_profile = "$SPOKE_AWS_PROFILE"
}