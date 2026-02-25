locals {
  cluster_info     = module.eks
  vpc_cidr         = var.vpc_cidr
  azs              = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
  enable_automode  = var.enable_automode
  use_ack          = var.use_ack
  enable_efs       = var.enable_efs
  name             = var.cluster_name
  environment      = var.environment
  fleet_member     = "control-plane"
  region           = data.aws_region.current.id
  cluster_version  = var.kubernetes_version
  argocd_namespace = var.argocd_namespace
  ack_namespace    = var.ack_namespace

  # Controller management modes
  ack_aws_managed     = var.ack_management_type == "aws_managed"
  ack_self_managed    = var.ack_management_type == "self_managed"
  kro_aws_managed     = var.kro_management_type == "aws_managed"
  kro_self_managed    = var.kro_management_type == "self_managed"
  argocd_aws_managed  = var.argocd_management_type == "aws_managed"
  argocd_self_managed = var.argocd_management_type == "self_managed"

  ack_role_enabled = var.enable_ack_capability || var.enable_ack_self_managed
  argocd_enabled   = var.enable_argocd_self_managed || var.enable_argocd_capability || var.argocd_bootstrap_enabled

  oidc_provider_id = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  # Account IDs - retrieved dynamically from AWS profiles
  csoc_account_id    = data.aws_caller_identity.current.account_id
  spoke_account_ids = var.spoke_account_ids

  gitops_addons_org_name = var.gitops_addons_org_name != "" ? var.gitops_addons_org_name : var.git_org_name
  gitops_fleet_org_name  = var.gitops_fleet_org_name != "" ? var.gitops_fleet_org_name : var.git_org_name

  gitops_addons_repo_url = "https://${var.gitops_addons_github_url}/${local.gitops_addons_org_name}/${var.gitops_addons_repo_name}.git"
  gitops_fleet_repo_url  = "https://${var.gitops_fleet_github_url}/${local.gitops_fleet_org_name}/${var.gitops_fleet_repo_name}.git"

  external_secrets = {
    namespace       = var.external_secrets_namespace
    service_account = var.external_secrets_service_account
  }

  aws_addons = {
    enable_external_secrets = try(var.addons.enable_external_secrets, false)
    enable_kro_eks_rgs      = try(var.addons.enable_kro_eks_rgs, false)
    enable_multi_acct       = try(var.addons.enable_multi_acct, false)
  }
  oss_addons = {
  }

  addons = merge(
    local.aws_addons,
    local.oss_addons,
    { fleet_member = local.fleet_member },
    { environment = local.environment },
    { ack_management_mode = var.ack_management_type },
    { kro_management_mode = var.kro_management_type },
    { argocd_management_mode = var.argocd_management_type },
    { enable_automode = tostring(local.enable_automode) },
    { enable_efs = tostring(local.enable_efs) },
    { kubernetes_version = local.cluster_version },
    { aws_cluster_name = local.cluster_info.cluster_name },
  )

  addons_metadata = merge(
    {
      aws_cluster_name = local.cluster_info.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = module.vpc.vpc_id
      use_ack          = local.use_ack
      ack_management_mode    = var.ack_management_type
      kro_management_mode    = var.kro_management_type
      argocd_management_mode = var.argocd_management_type
      enable_automode        = tostring(local.enable_automode)
      enable_efs             = tostring(local.enable_efs)
    },
    {
      addons_repo_url      = local.gitops_addons_repo_url
      addons_repo_path     = var.gitops_addons_repo_path
      addons_repo_basepath = var.gitops_addons_repo_base_path
      addons_repo_revision = var.gitops_addons_repo_revision
    },
    {
      fleet_repo_url      = local.gitops_fleet_repo_url
      fleet_repo_path     = var.gitops_fleet_repo_path
      fleet_repo_basepath = var.gitops_fleet_repo_base_path
      fleet_repo_revision = var.gitops_fleet_repo_revision
    },
    {
      external_secrets_namespace       = local.external_secrets.namespace
      external_secrets_service_account = local.external_secrets.service_account
    }
  )

  tags = merge(
    {
      Blueprint  = local.name
      GithubRepo = local.gitops_addons_repo_url
    },
    var.tags
  )
}
