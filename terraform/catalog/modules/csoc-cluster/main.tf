################################################################################
# CSOC Cluster Composite Module
#
# Compatibility wrapper that composes the split AWS foundation and in-cluster
# bootstrap modules into the existing deployable unit. Intended to be called
# from terraform/env/aws/csoc-cluster/ until state migration is complete.
################################################################################

# ─── CSOC AWS Foundation: VPC, EKS, OIDC, IAM, AWS capabilities ──────────────

module "aws_csoc_foundation" {
  source = "../aws-csoc-foundation"

  # AWS
  aws_profile       = var.aws_profile
  spoke_account_ids = var.spoke_account_ids

  # Naming
  csoc_alias           = var.csoc_alias
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  public_subnet_tags   = var.public_subnet_tags
  private_subnet_tags  = var.private_subnet_tags
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway

  # EKS
  kubernetes_version                       = var.kubernetes_version
  environment                              = var.environment
  cluster_endpoint_public_access           = var.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = var.cluster_compute_config
  enable_automode                          = var.enable_automode
  enable_efs                               = var.enable_efs

  # ArgoCD
  argocd_namespace        = var.argocd_namespace
  argocd_chart_version    = var.argocd_chart_version
  argocd_chart_repository = var.argocd_chart_repository
  argocd_values           = var.argocd_values

  # External Secrets
  external_secrets_namespace       = var.external_secrets_namespace
  external_secrets_service_account = var.external_secrets_service_account

  # Addons
  addons = var.addons

  # Argo CD Bootstrap metadata only. In-cluster resources are managed by the
  # csoc_in_cluster_bootstrap module below.
  argocd_bootstrap_enabled = var.argocd_bootstrap_enabled

  # Controller management
  ack_management_type        = var.ack_management_type
  kro_management_type        = var.kro_management_type
  argocd_management_type     = var.argocd_management_type
  enable_ack_capability      = var.enable_ack_capability
  enable_kro_capability      = var.enable_kro_capability
  enable_argocd_capability   = var.enable_argocd_capability
  enable_ack_self_managed    = var.enable_ack_self_managed
  enable_argocd_self_managed = var.enable_argocd_self_managed
  ack_namespace              = var.ack_namespace
  use_ack                    = var.use_ack

  # GitOps — Addons
  git_org_name                 = var.git_org_name
  gitops_addons_repo_name      = var.gitops_addons_repo_name
  gitops_addons_repo_path      = var.gitops_addons_repo_path
  gitops_addons_repo_base_path = var.gitops_addons_repo_base_path
  gitops_addons_repo_revision  = var.gitops_addons_repo_revision
  gitops_addons_github_url     = var.gitops_addons_github_url
  gitops_addons_org_name       = var.gitops_addons_org_name

  # GitOps — Fleet
  gitops_fleet_repo_name      = var.gitops_fleet_repo_name
  gitops_fleet_repo_path      = var.gitops_fleet_repo_path
  gitops_fleet_repo_base_path = var.gitops_fleet_repo_base_path
  gitops_fleet_repo_revision  = var.gitops_fleet_repo_revision
  gitops_fleet_github_url     = var.gitops_fleet_github_url
  gitops_fleet_org_name       = var.gitops_fleet_org_name

  # Tags
  tags = var.tags
}

# ─── CSOC In-Cluster Bootstrap: Argo CD install and first GitOps seed ─────────

module "csoc_in_cluster_bootstrap" {
  source = "../csoc-in-cluster-bootstrap"

  # Toggle
  enabled = var.argocd_bootstrap_enabled || var.enable_argocd_self_managed || var.enable_argocd_capability

  # Cluster connectivity — wired directly from foundation outputs
  aws_profile                        = var.aws_profile
  region                             = var.region
  cluster_name                       = module.aws_csoc_foundation.cluster_name
  cluster_endpoint                   = module.aws_csoc_foundation.cluster_endpoint
  cluster_certificate_authority_data = module.aws_csoc_foundation.cluster_certificate_authority_data
  foundation_dependency_token        = module.aws_csoc_foundation.foundation_ready_token
  csoc_account_id                    = module.aws_csoc_foundation.csoc_account_id

  # Argo CD install
  argocd_namespace              = module.aws_csoc_foundation.argocd_namespace
  argocd_chart_version          = var.argocd_chart_version
  argocd_chart_repository       = var.argocd_chart_repository
  argocd_values                 = var.argocd_values
  enable_argocd_self_managed    = var.enable_argocd_self_managed
  enable_argocd_capability      = var.enable_argocd_capability
  argocd_self_managed_role_arn  = module.aws_csoc_foundation.argocd_self_managed_role_arn
  argocd_bootstrap_enabled      = var.argocd_bootstrap_enabled
  argocd_cluster_secret_name    = var.argocd_cluster_secret_name
  argocd_cluster_labels         = module.aws_csoc_foundation.argocd_cluster_labels_base
  argocd_cluster_annotations    = module.aws_csoc_foundation.argocd_cluster_annotations_base
  ack_self_managed_role_arn     = module.aws_csoc_foundation.ack_csoc_role_arn
  spoke_account_ids             = module.aws_csoc_foundation.spoke_account_ids

  # Secrets Manager repos
  ssm_repo_secret_names = var.ssm_repo_secret_names

  # Output paths
  outputs_dir = var.outputs_dir
  stack_dir   = var.stack_dir
}
