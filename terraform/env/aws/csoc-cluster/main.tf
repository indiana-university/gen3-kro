################################################################################
# CSOC Environment — Thin Root Module
#
# Single module call into the csoc-cluster catalog composite module.
# All provider, backend, and version configuration lives here.
# Business logic (aws-csoc + argocd-bootstrap composition) lives in the
# catalog module at terraform/catalog/modules/csoc-cluster/.
################################################################################

module "csoc_cluster" {
  source = "../../../catalog/modules/csoc-cluster"

  # Region
  region = var.region

  # AWS
  aws_profile = var.aws_profile
  # Derive spoke_account_ids from the structured spokes list so there is a
  # single source of truth (spokes[].provider.account_id in config JSON).
  spoke_account_ids = {
    for s in var.spokes : s.alias => s.provider.account_id
    if try(s.enabled, false)
  }
  # Derive spoke_dns_config from spokes[].dns (hosted zone ID + name per spoke).
  # Only includes spokes that are enabled and have dns config defined.
  spoke_dns_config = {
    for s in var.spokes : s.alias => {
      hosted_zone_id   = try(s.dns.hosted_zone_id, "")
      hosted_zone_name = try(s.dns.hosted_zone_name, "")
    }
    if try(s.enabled, false)
  }

  # VPC
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  public_subnet_tags   = var.public_subnet_tags
  private_subnet_tags  = var.private_subnet_tags
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway

  # EKS
  csoc_alias                               = var.csoc_alias
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

  # ArgoCD Bootstrap
  argocd_bootstrap_enabled   = var.argocd_bootstrap_enabled
  argocd_cluster_secret_name = var.argocd_cluster_secret_name
  ssm_repo_secret_names      = var.ssm_repo_secret_names
  outputs_dir                = var.outputs_dir
  stack_dir                  = var.stack_dir
}
