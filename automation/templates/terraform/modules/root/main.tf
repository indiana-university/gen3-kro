################################################################################
# Hub Cluster Modules
################################################################################

module "kind-hub" {
  source  = "../kind-hub"
  #if environment is dev or staging
  count = var.environment == "dev" || var.environment == "staging" ? 1 : 0
  # Cluster configuration
  cluster_name = var.cluster_name
  kubernetes_version   = var.kubernetes_version
  kubeconfig_dir       = var.kubeconfig_dir
  providers = {
    kind       = kind.dev
    kubernetes = kubernetes.dev
    helm       = helm.dev
  }

}

module "eks-hub" {
  source  = "../eks-hub"
  # if environment is prod
  count = var.environment == "prod" ? 1 : 0
  # Authentication and authorization
  aws_region  = var.hub_aws_region
  account_ids = var.account_ids
  # Cluster configuration
  vpc_name           = var.vpc_name
  kubernetes_version = var.kubernetes_version
  cluster_name       = var.cluster_name
  tenant             = var.tenant
  environment        = var.environment
  #Cluster addons configuration
  ackCreate             = var.ackCreate
  use_ack               = var.use_ack
  enable_addon_selector = var.enable_addon_selector
  enable_efs            = var.enable_efs
  addons                = var.addons
  # local variables
  name                         = local.name
  vpc_cidr                     = local.vpc_cidr
  cluster_info                 = local.cluster_info
  private_key_paths            = local.private_key_paths
  azs                          = local.azs
  cluster_version              = local.cluster_version
  valid_policies               = local.valid_policies
  aws_addons                   = local.aws_addons
  external_secrets             = local.external_secrets
  aws_load_balancer_controller = local.aws_load_balancer_controller
  # GitOps configurations
  gitops_addons_app_private_key_ssm_path   = var.gitops_addons_app_private_key_ssm_path
  gitops_fleet_app_private_key_ssm_path    = var.gitops_fleet_app_private_key_ssm_path
  gitops_platform_app_private_key_ssm_path = var.gitops_platform_app_private_key_ssm_path
  gitops_workload_app_private_key_ssm_path = var.gitops_workload_app_private_key_ssm_path
  # tags
  tags = var.tags
}
################################################################################
# AgroCD Module
################################################################################
module "argocd" {
  source  = "../argocd"
  # Authentication and authorization
  aws_region  = var.hub_aws_region
  account_ids = var.account_ids
  # Cluster configuration
  vpc_name           = var.vpc_name
  kubernetes_version = var.kubernetes_version
  cluster_name       = var.cluster_name
  enable_automode    = var.enable_automode
  tenant             = var.tenant
  environment        = var.environment
  #Cluster addons configuration
  ackCreate             = var.ackCreate
  use_ack               = var.use_ack
  enable_addon_selector = var.enable_addon_selector
  enable_efs            = var.enable_efs
  addons                = var.addons
  # local variables
  vpc_id                               = local.vpc_id
  local_addons                         = local.addons
  cluster_info                         = local.cluster_info
  argocd_namespace                     = local.argocd_namespace
  argocd_chart_version                 = var.argocd_chart_version
  argocd_hub_pod_identity_iam_role_arn = local.argocd_hub_pod_identity_iam_role_arn
  argocd_apps                          = local.argocd_apps
  addons_metadata                      = local.addons_metadata
  # GitOps Addons configuration
  gitops_addons_github_url     = var.gitops_addons_github_url
  gitops_addons_org_name       = var.gitops_addons_org_name
  gitops_addons_repo_name      = var.gitops_addons_repo_name
  gitops_addons_repo_base_path = var.gitops_addons_repo_base_path
  gitops_addons_repo_path      = var.gitops_addons_repo_path
  gitops_addons_repo_revision  = var.gitops_addons_repo_revision
  # GitOps Fleet configuration
  gitops_fleet_github_url     = var.gitops_fleet_github_url
  gitops_fleet_org_name       = var.gitops_fleet_org_name
  gitops_fleet_repo_name      = var.gitops_fleet_repo_name
  gitops_fleet_repo_base_path = var.gitops_fleet_repo_base_path
  gitops_fleet_repo_path      = var.gitops_fleet_repo_path
  gitops_fleet_repo_revision  = var.gitops_fleet_repo_revision
  # GitOps Platform configuration
  gitops_platform_github_url     = var.gitops_platform_github_url
  gitops_platform_org_name       = var.gitops_platform_org_name
  gitops_platform_repo_name      = var.gitops_platform_repo_name
  gitops_platform_repo_base_path = var.gitops_platform_repo_base_path
  gitops_platform_repo_path      = var.gitops_platform_repo_path
  gitops_platform_repo_revision  = var.gitops_platform_repo_revision
  # GitOps Workload configuration
  gitops_workload_github_url     = var.gitops_workload_github_url
  gitops_workload_org_name       = var.gitops_workload_org_name
  gitops_workload_repo_name      = var.gitops_workload_repo_name
  gitops_workload_repo_base_path = var.gitops_workload_repo_base_path
  gitops_workload_repo_path      = var.gitops_workload_repo_path
  gitops_workload_repo_revision  = var.gitops_workload_repo_revision
  # tags
  tags = var.tags
}
################################################################################
# Git Secrets Module
################################################################################
module "git-secrets" {
  source = "../git-secrets"
  aws_region   = var.hub_aws_region
  cluster_info = local.cluster_info
  outputs_dir  = var.outputs_dir
  # Local varianbles
  git_secrets      = local.git_secrets
  argocd_namespace = local.argocd_namespace
  integrations     = local.integrations
    # GitOps Addons configuration
  gitops_addons_github_url               = var.gitops_addons_github_url
  gitops_addons_org_name                 = var.gitops_addons_org_name
  gitops_addons_app_id                   = var.gitops_addons_app_id
  gitops_addons_app_installation_id      = var.gitops_addons_app_installation_id
  gitops_addons_app_private_key_ssm_path = var.gitops_addons_app_private_key_ssm_path
  gitops_addons_repo_name                = var.gitops_addons_repo_name
  # GitOps Fleet configuration
  gitops_fleet_github_url               = var.gitops_fleet_github_url
  gitops_fleet_org_name                 = var.gitops_fleet_org_name
  gitops_fleet_app_id                   = var.gitops_fleet_app_id
  gitops_fleet_app_installation_id      = var.gitops_fleet_app_installation_id
  gitops_fleet_app_private_key_ssm_path = var.gitops_fleet_app_private_key_ssm_path
  gitops_fleet_repo_name                = var.gitops_fleet_repo_name
  # GitOps Platform configuration
  gitops_platform_github_url               = var.gitops_platform_github_url
  gitops_platform_org_name                 = var.gitops_platform_org_name
  gitops_platform_app_id                   = var.gitops_platform_app_id
  gitops_platform_app_installation_id      = var.gitops_platform_app_installation_id
  gitops_platform_app_private_key_ssm_path = var.gitops_platform_app_private_key_ssm_path
  gitops_platform_repo_name                = var.gitops_platform_repo_name
  # GitOps Workload configuration
  gitops_workload_github_url               = var.gitops_workload_github_url
  gitops_workload_org_name                 = var.gitops_workload_org_name
  gitops_workload_app_id                   = var.gitops_workload_app_id
  gitops_workload_app_installation_id      = var.gitops_workload_app_installation_id
  gitops_workload_app_private_key_ssm_path = var.gitops_workload_app_private_key_ssm_path
  gitops_workload_repo_name                = var.gitops_workload_repo_name
}