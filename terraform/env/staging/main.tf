################################################################################
# Hub Cluster
################################################################################

module "root" {
  source  = "../../modules/root"
  # Authentication and authorization
  hub_aws_region    = var.hub_aws_region
  hub_aws_profile   = var.hub_aws_profile
  # Cluster configuration
  vpc_name           = var.vpc_name
  kubernetes_version = var.kubernetes_version
  kubeconfig_dir     = var.kubeconfig_dir
  cluster_name       = var.cluster_name
  enable_automode    = var.enable_automode
  environment        = var.environment
  #Cluster addons configuration
  ackCreate             = var.ackCreate
  use_ack               = var.use_ack
  enable_addon_selector = var.enable_addon_selector
  enable_efs            = var.enable_efs
  addons                = var.addons
  ack_services          = var.ack_services
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
  # GitOps configurations
  gitops_addons_app_private_key_ssm_path   = var.gitops_addons_app_private_key_ssm_path
  gitops_fleet_app_private_key_ssm_path    = var.gitops_fleet_app_private_key_ssm_path
  gitops_platform_app_private_key_ssm_path = var.gitops_platform_app_private_key_ssm_path
  gitops_workload_app_private_key_ssm_path = var.gitops_workload_app_private_key_ssm_path
  # GitOps App IDs
  gitops_addons_app_id   = var.gitops_addons_app_id
  gitops_fleet_app_id    = var.gitops_fleet_app_id
  gitops_platform_app_id = var.gitops_platform_app_id
  gitops_workload_app_id = var.gitops_workload_app_id 
  # GitOps App Installation IDs
  gitops_addons_app_installation_id   = var.gitops_addons_app_installation_id
  gitops_fleet_app_installation_id    = var.gitops_fleet_app_installation_id
  gitops_platform_app_installation_id = var.gitops_platform_app_installation_id
  gitops_workload_app_installation_id = var.gitops_workload_app_installation_id
  # tags
  tags = var.tags
  # Configuration outputs
  outputs_dir = var.outputs_dir
}