locals {
  repo_root    = get_repo_root()
  modules_path = "terraform/catalog/modules"
  units_path   = "${local.repo_root}/terraform/catalog/units"
  config       = jsondecode(file("${local.repo_root}/config/shared.auto.tfvars.json"))

  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "csoc_alias", "csoc")
  cluster_name    = "${local.csoc_alias}-csoc-cluster"
  state_bucket    = lookup(local.config, "backend_bucket", "")
  backend_region  = lookup(local.config, "backend_region", local.region)
  iam_base_path   = lookup(local.config, "iam_base_path", "iam")

  enabled_spokes  = [for spoke in lookup(local.config, "spokes", []) : spoke if lookup(spoke, "enabled", false)]
  spokes_by_alias = { for spoke in local.enabled_spokes : spoke.alias => spoke }
  spoke_alias     = get_env("TG_SPOKE_ALIAS", length(local.enabled_spokes) == 1 ? local.enabled_spokes[0].alias : "")
  selected_spoke  = local.spokes_by_alias[local.spoke_alias]

  selected_provider   = lookup(local.selected_spoke, "provider", {})
  selected_account_id = lookup(local.selected_provider, "account_id", "")
  selected_profile = (
    local.selected_account_id == local.csoc_account_id
    ? local.profile
    : lookup(local.selected_provider, "aws_profile", local.profile)
  )
  selected_region = lookup(local.selected_provider, "region", local.region)

  policy_file = "inline-policy.json"
  selected_policy = try(
    jsondecode(templatefile("${local.repo_root}/${local.iam_base_path}/${local.spoke_alias}/ack/${local.policy_file}", { account_id = local.selected_account_id })),
    jsondecode(templatefile("${local.repo_root}/${local.iam_base_path}/_default/ack/${local.policy_file}", { account_id = local.selected_account_id }))
  )
  selected_roles = {
    ack-controller = {
      enabled          = true
      managed_policies = []
      custom_policies  = [for statement in local.selected_policy.Statement : jsonencode(statement)]
      resource_types   = []
    }
  }

  spoke_account_ids = {
    for spoke in local.enabled_spokes :
    spoke.alias => lookup(lookup(spoke, "provider", {}), "account_id", "")
  }
  spoke_role_arns = {
    for alias, account_id in local.spoke_account_ids :
    alias => "arn:aws:iam::${account_id}:role/${alias}-ack-controller-access-role"
  }

  git_org_name    = lookup(local.config, "git_org_name", "kro-run")
  addons_org_name = lookup(local.config, "gitops_addons_org_name", "") != "" ? lookup(local.config, "gitops_addons_org_name", "") : local.git_org_name
  fleet_org_name  = lookup(local.config, "gitops_fleet_org_name", "") != "" ? lookup(local.config, "gitops_fleet_org_name", "") : local.git_org_name
  addons_repo_url = "https://${lookup(local.config, "gitops_addons_github_url", "github.com")}/${local.addons_org_name}/${lookup(local.config, "gitops_addons_repo_name", "kro")}.git"
  fleet_repo_url  = "https://${lookup(local.config, "gitops_fleet_github_url", "github.com")}/${local.fleet_org_name}/${lookup(local.config, "gitops_fleet_repo_name", "kro")}.git"
  addons          = lookup(local.config, "addons", {})
  environment     = lookup(local.config, "environment", "control-plane")

  argocd_cluster_labels = {
    enable_external_secrets = try(local.addons.enable_external_secrets, false)
    enable_kro_csoc_rgs     = try(coalesce(try(local.addons.enable_kro_csoc_rgs, null), try(local.addons.enable_kro_eks_rgs, null)), false)
    enable_multi_acct       = try(local.addons.enable_multi_acct, false)
    fleet_member            = "control-plane"
    environment             = local.environment
    ack_management_mode     = lookup(local.config, "ack_management_type", "self_managed")
    cluster_type            = "eks"
  }
  argocd_cluster_annotations = {
    aws_cluster_name     = local.cluster_name
    aws_region           = local.region
    addons_repo_url      = local.addons_repo_url
    addons_repo_basepath = lookup(local.config, "gitops_addons_repo_base_path", "argocd/")
    addons_repo_path     = lookup(local.config, "gitops_addons_repo_path", "bootstrap")
    addons_repo_revision = lookup(local.config, "gitops_addons_repo_revision", "main")
    fleet_repo_url       = local.fleet_repo_url
    fleet_repo_basepath  = lookup(local.config, "gitops_fleet_repo_base_path", "argocd/")
    fleet_repo_path      = lookup(local.config, "gitops_fleet_repo_path", "bootstrap")
    fleet_repo_revision  = lookup(local.config, "gitops_fleet_repo_revision", "main")
  }

  tags = merge({ Terraform = "true", ManagedBy = "terragrunt", Stack = "spoke-fleet-update" }, lookup(local.config, "tags", {}))
}

unit "aws_spoke_access_iam" {
  source = "${local.units_path}/aws-spoke-access-iam"
  path   = "aws-spoke-access-iam-${local.spoke_alias}"

  values = {
    modules_path         = local.modules_path
    state_bucket         = local.state_bucket
    backend_region       = local.backend_region
    backend_profile      = local.profile
    state_key            = "spokes/${local.spoke_alias}/aws-spoke-access-iam/terraform.tfstate"
    controller_state_key = "csoc/aws-csoc-controller-iam/terraform.tfstate"
    operator_state_key   = "prereq/aws-csoc-operator-iam/terraform.tfstate"
    spoke_alias          = local.spoke_alias
    spoke_profile        = local.selected_profile
    spoke_region         = local.selected_region
    cluster_name         = local.cluster_name
    roles                = local.selected_roles
    tags                 = local.tags
  }
}

unit "aws_csoc_to_spoke_access" {
  source = "${local.units_path}/aws-csoc-to-spoke-access"
  path   = "aws-csoc-to-spoke-access"

  values = {
    modules_path            = local.modules_path
    state_bucket            = local.state_bucket
    backend_region          = local.backend_region
    profile                 = local.profile
    region                  = local.region
    state_key               = "csoc/aws-csoc-to-spoke-access/terraform.tfstate"
    controller_state_key    = "csoc/aws-csoc-controller-iam/terraform.tfstate"
    spoke_unit_path         = "../aws-spoke-access-iam-${local.spoke_alias}"
    selected_spoke_alias    = local.spoke_alias
    selected_spoke_role_arn = local.spoke_role_arns[local.spoke_alias]
    spoke_role_arns         = local.spoke_role_arns
    policy_name             = "${local.csoc_alias}-ack-assume-spoke-roles"
  }
}

unit "gitops_argocd_bootstrap" {
  source = "${local.units_path}/gitops-argocd-bootstrap"
  path   = "gitops-argocd-bootstrap"

  values = {
    modules_path               = local.modules_path
    state_bucket               = local.state_bucket
    backend_region             = local.backend_region
    profile                    = local.profile
    region                     = local.region
    state_key                  = "csoc/gitops-argocd-bootstrap/terraform.tfstate"
    cluster_state_key          = "csoc/aws-csoc-cluster/terraform.tfstate"
    controller_state_key       = "csoc/aws-csoc-controller-iam/terraform.tfstate"
    argocd_install_state_key   = "csoc/gitops-argocd-install/terraform.tfstate"
    spoke_access_unit_path     = "../aws-csoc-to-spoke-access"
    spoke_role_arns            = local.spoke_role_arns
    enabled                    = lookup(local.config, "argocd_bootstrap_enabled", true)
    ssm_repo_secret_names      = lookup(local.config, "ssm_repo_secret_names", { repos = [] })
    argocd_cluster_secret_name = lookup(local.config, "argocd_cluster_secret_name", "")
    argocd_cluster_labels      = local.argocd_cluster_labels
    argocd_cluster_annotations = local.argocd_cluster_annotations
    spoke_account_ids          = local.spoke_account_ids
  }
}
