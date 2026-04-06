locals {
  cluster_info     = module.eks
  vpc_cidr         = var.vpc_cidr
  azs              = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
  enable_automode  = var.enable_automode
  enable_efs       = var.enable_efs
  name             = var.csoc_alias
  cluster_name     = "${local.name}-csoc-cluster"
  vpc_name         = "${local.name}-csoc-vpc"
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
    enable_kro_csoc_rgs     = try(coalesce(try(var.addons.enable_kro_csoc_rgs, null), try(var.addons.enable_kro_eks_rgs, null)), false)
    enable_multi_acct       = try(var.addons.enable_multi_acct, false)
  }
  oss_addons = {
  }

  # Labels used by ApplicationSet selectors only — do not add keys not referenced
  # in a selector matchLabels / matchExpressions block.
  addons = merge(
    local.aws_addons,   # enable_external_secrets, enable_kro_csoc_rgs, enable_multi_acct
    local.oss_addons,
    { fleet_member        = local.fleet_member },
    { environment         = local.environment },
    { ack_management_mode = var.ack_management_type }, # selector: self_managed / aws_managed
    { cluster_type        = "eks" },                   # selector: eks / kind
  )

  # Annotations consumed by ArgoCD ApplicationSet templates via
  # {{.metadata.annotations.<key>}}. Only add keys that are referenced
  # in a template expression — unused annotations are noise.
  addons_metadata = merge(
    {
      # Cluster identity — used by ack-multi-acct (clusterName) and ACK SA IRSA (aws_region)
      aws_cluster_name = local.cluster_info.cluster_name
      aws_region       = local.region
    },
    {
      # GitOps — addons ApplicationSet source
      addons_repo_url      = local.gitops_addons_repo_url
      addons_repo_basepath = var.gitops_addons_repo_base_path
      addons_repo_path     = var.gitops_addons_repo_path
      addons_repo_revision = var.gitops_addons_repo_revision
      addons_config_path   = "argocd/addons/addons.yaml"
    },
    {
      # GitOps — fleet + workloads ApplicationSets
      fleet_repo_url      = local.gitops_fleet_repo_url
      fleet_repo_basepath = var.gitops_fleet_repo_base_path
      fleet_repo_path     = var.gitops_fleet_repo_path
      fleet_repo_revision = var.gitops_fleet_repo_revision
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
