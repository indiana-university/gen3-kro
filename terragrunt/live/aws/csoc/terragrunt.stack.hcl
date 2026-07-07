###############################################################################
# CSOC Stack — Terragrunt-first provisioning path
#
# Orchestrates CSOC infrastructure in roadmap order:
#   1. developer_identity
#   2. csoc_foundation
#   3. spoke_iam
#   4. csoc_in_cluster_bootstrap
#
# Source of truth: config/shared.auto.tfvars.json
# State keys are intentionally split by function for the later state-migration
# phase. The deprecated terragrunt/live/aws/iam-setup stack remains available
# until state has been migrated.
###############################################################################

locals {
  repo_root = get_repo_root()

  modules_path = "terraform/catalog/modules"
  units_path   = "${local.repo_root}/terraform/catalog/units"

  config_file = "${local.repo_root}/config/shared.auto.tfvars.json"
  config      = jsondecode(file(local.config_file))

  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "csoc_alias", "csoc")
  cluster_name    = "${local.csoc_alias}-csoc-cluster"
  state_bucket    = lookup(local.config, "backend_bucket", "")

  spokes_config         = lookup(local.config, "spokes", [])
  retired_spokes_config = lookup(local.config, "retired_spokes", [])
  dev_identity_config   = lookup(local.config, "developer_identity", {})

  spokes = [
    for spoke in local.spokes_config :
    spoke if lookup(spoke, "enabled", false)
  ]

  provider_spokes = concat(local.spokes_config, local.retired_spokes_config)

  spoke_account_ids = {
    for spoke in local.spokes :
    spoke.alias => lookup(lookup(spoke, "provider", {}), "account_id", "")
  }

  iam_base_path   = lookup(local.config, "iam_base_path", "iam")
  iam_policy_file = "inline-policy.json"

  spoke_ack_policy_documents = {
    for spoke in local.spokes :
    spoke.alias => try(
      jsondecode(templatefile("${local.repo_root}/${local.iam_base_path}/${spoke.alias}/ack/${local.iam_policy_file}", {
        account_id = lookup(lookup(spoke, "provider", {}), "account_id", local.csoc_account_id)
      })),
      jsondecode(templatefile("${local.repo_root}/${local.iam_base_path}/_default/ack/${local.iam_policy_file}", {
        account_id = lookup(lookup(spoke, "provider", {}), "account_id", local.csoc_account_id)
      })),
      null
    )
  }

  spoke_ack_policy_sources = {
    for spoke in local.spokes :
    spoke.alias => (
      fileexists("${local.repo_root}/${local.iam_base_path}/${spoke.alias}/ack/${local.iam_policy_file}") ?
      "${local.iam_base_path}/${spoke.alias}/ack/${local.iam_policy_file}" : (
        fileexists("${local.repo_root}/${local.iam_base_path}/_default/ack/${local.iam_policy_file}") ?
        "${local.iam_base_path}/_default/ack/${local.iam_policy_file}" : "none"
      )
    )
  }

  spoke_ack_roles = {
    for spoke_alias, policy_source in local.spoke_ack_policy_sources :
    spoke_alias => (
      policy_source != "none" ? {
        ack-controller = {
          enabled          = true
          managed_policies = []
          custom_policies = [
            for stmt in try(local.spoke_ack_policy_documents[spoke_alias].Statement, []) :
            jsonencode(stmt)
          ]
          resource_types = []
        }
      } : {}
    )
  }

  spoke_configs = {
    for spoke in local.spokes : spoke.alias => {
      profile = (
        local.csoc_account_id != "" && lookup(lookup(spoke, "provider", {}), "account_id", "") == local.csoc_account_id
        ? local.profile
        : try(lookup(lookup(spoke, "provider", {}), "aws_profile", local.profile), local.profile)
      )
      region = try(lookup(lookup(spoke, "provider", {}), "region", local.region), local.region)
      roles  = lookup(local.spoke_ack_roles, spoke.alias, {})
    }
  }

  provider_spoke_configs = {
    for spoke in local.provider_spokes : spoke.alias => {
      profile = (
        local.csoc_account_id != "" && lookup(lookup(spoke, "provider", {}), "account_id", "") == local.csoc_account_id
        ? local.profile
        : try(lookup(lookup(spoke, "provider", {}), "aws_profile", local.profile), local.profile)
      )
      region = try(lookup(lookup(spoke, "provider", {}), "region", local.region), local.region)
    }
  }

  dev_iam_user_name              = lookup(local.dev_identity_config, "iam_user_name", "")
  devcontainer_role_suffix       = lookup(local.dev_identity_config, "devcontainer_role_suffix", "devcontainer-role")
  devcontainer_role_name         = "${local.csoc_alias}-${local.devcontainer_role_suffix}"
  devcontainer_mfa_device_suffix = lookup(local.dev_identity_config, "mfa_device_suffix", "devcontainer-mfa")
  devcontainer_mfa_device_name   = "${local.csoc_alias}-${local.devcontainer_mfa_device_suffix}"
  dev_create_virtual_mfa         = lookup(local.dev_identity_config, "create_virtual_mfa", true)
  dev_assume_requires_mfa        = lookup(local.dev_identity_config, "assume_requires_mfa", true)
  dev_attach_user_policy         = lookup(local.dev_identity_config, "attach_user_policy", true)
  dev_policy_filename            = lookup(local.dev_identity_config, "policy_filename", "gen3-test-developer.json")
  dev_role_max_session_secs      = lookup(local.dev_identity_config, "role_max_session_duration", 43200)
  allow_devcontainer_assume_role = lookup(local.dev_identity_config, "allow_devcontainer_assume_role", true)

  base_tags = merge(
    { Terraform = "true", ManagedBy = "terragrunt" },
    lookup(local.config, "tags", {})
  )

  foundation_values = {
    modules_path = local.modules_path

    profile      = local.profile
    region       = local.region
    state_bucket = local.state_bucket

    csoc_alias           = local.csoc_alias
    spoke_account_ids    = local.spoke_account_ids
    vpc_cidr             = lookup(local.config, "vpc_cidr", "10.0.0.0/16")
    availability_zones   = lookup(local.config, "availability_zones", [])
    private_subnet_cidrs = lookup(local.config, "private_subnet_cidrs", [])
    public_subnet_cidrs  = lookup(local.config, "public_subnet_cidrs", [])
    public_subnet_tags   = lookup(local.config, "public_subnet_tags", {})
    private_subnet_tags  = lookup(local.config, "private_subnet_tags", {})
    enable_nat_gateway   = lookup(local.config, "enable_nat_gateway", true)
    single_nat_gateway   = lookup(local.config, "single_nat_gateway", true)

    kubernetes_version                       = lookup(local.config, "kubernetes_version", "1.35")
    environment                              = lookup(local.config, "environment", "control-plane")
    cluster_endpoint_public_access           = lookup(local.config, "cluster_endpoint_public_access", true)
    enable_cluster_creator_admin_permissions = lookup(local.config, "enable_cluster_creator_admin_permissions", true)
    cluster_compute_config                   = lookup(local.config, "cluster_compute_config", { enabled = true, node_pools = ["general-purpose", "system"] })
    enable_automode                          = lookup(local.config, "enable_automode", true)
    enable_efs                               = lookup(local.config, "enable_efs", false)

    argocd_namespace        = lookup(local.config, "argocd_namespace", "argocd")
    argocd_chart_version    = lookup(local.config, "argocd_chart_version", "7.0.0")
    argocd_chart_repository = lookup(local.config, "argocd_chart_repository", "https://argoproj.github.io/argo-helm")
    argocd_values           = lookup(local.config, "argocd_values", {})

    external_secrets_namespace       = lookup(local.config, "external_secrets_namespace", "external-secrets")
    external_secrets_service_account = lookup(local.config, "external_secrets_service_account", "external-secrets-sa")

    addons = lookup(local.config, "addons", {})

    argocd_bootstrap_enabled = lookup(local.config, "argocd_bootstrap_enabled", true)

    ack_management_type        = lookup(local.config, "ack_management_type", "self_managed")
    kro_management_type        = lookup(local.config, "kro_management_type", "self_managed")
    argocd_management_type     = lookup(local.config, "argocd_management_type", "self_managed")
    enable_ack_capability      = lookup(local.config, "enable_ack_capability", false)
    enable_kro_capability      = lookup(local.config, "enable_kro_capability", false)
    enable_argocd_capability   = lookup(local.config, "enable_argocd_capability", false)
    enable_ack_self_managed    = lookup(local.config, "enable_ack_self_managed", false)
    enable_argocd_self_managed = lookup(local.config, "enable_argocd_self_managed", false)
    ack_namespace              = lookup(local.config, "ack_namespace", "ack")
    use_ack                    = lookup(local.config, "use_ack", true)

    git_org_name                 = lookup(local.config, "git_org_name", "kro-run")
    gitops_addons_repo_name      = lookup(local.config, "gitops_addons_repo_name", "kro")
    gitops_addons_repo_path      = lookup(local.config, "gitops_addons_repo_path", "bootstrap")
    gitops_addons_repo_base_path = lookup(local.config, "gitops_addons_repo_base_path", "argocd/")
    gitops_addons_repo_revision  = lookup(local.config, "gitops_addons_repo_revision", "main")
    gitops_addons_github_url     = lookup(local.config, "gitops_addons_github_url", "github.com")
    gitops_addons_org_name       = lookup(local.config, "gitops_addons_org_name", "")

    gitops_fleet_repo_name      = lookup(local.config, "gitops_fleet_repo_name", "kro")
    gitops_fleet_repo_path      = lookup(local.config, "gitops_fleet_repo_path", "bootstrap")
    gitops_fleet_repo_base_path = lookup(local.config, "gitops_fleet_repo_base_path", "argocd/")
    gitops_fleet_repo_revision  = lookup(local.config, "gitops_fleet_repo_revision", "main")
    gitops_fleet_github_url     = lookup(local.config, "gitops_fleet_github_url", "github.com")
    gitops_fleet_org_name       = lookup(local.config, "gitops_fleet_org_name", "")

    tags = local.base_tags
  }
}

unit "developer_identity" {
  source = "${local.units_path}/developer-identity"
  path   = "developer-identity"

  values = {
    modules_path = local.modules_path

    profile = local.profile
    region  = local.region

    state_bucket = local.state_bucket
    state_key    = "iam-setup/developer-identity/terraform.tfstate"

    iam_user_name = local.dev_iam_user_name

    devcontainer_role_name    = local.devcontainer_role_name
    role_max_session_duration = local.dev_role_max_session_secs
    assume_requires_mfa       = local.dev_assume_requires_mfa
    assume_principal_arns     = []
    attach_user_policy        = local.dev_attach_user_policy

    mfa_device_name    = local.devcontainer_mfa_device_name
    create_virtual_mfa = local.dev_create_virtual_mfa

    policy_filename = local.dev_policy_filename
    inline_policy = templatefile("${local.repo_root}/iam/developer-identity/${local.dev_policy_filename}", merge(
      {
        account_id = local.csoc_account_id
        region     = local.region
      },
      {
        for spoke in local.spokes_config :
        "${spoke.alias}_account_id" => lookup(lookup(spoke, "provider", {}), "account_id", local.csoc_account_id)
      }
    ))

    outputs_dir = "${local.repo_root}/outputs"

    tags = local.base_tags
  }
}

unit "csoc_foundation" {
  source = "${local.units_path}/csoc-foundation"
  path   = "csoc-foundation"

  values = merge(local.foundation_values, {
    state_key = "csoc/foundation/terraform.tfstate"
  })
}

unit "spoke_iam" {
  source = "${local.units_path}/spoke-iam"
  path   = "spoke-iam"

  values = {
    modules_path = local.modules_path

    state_bucket = local.state_bucket
    state_key    = "csoc/spoke-iam/terraform.tfstate"

    region       = local.region
    csoc_profile = local.profile

    csoc_foundation_path = "../csoc-foundation"
    cluster_name         = local.cluster_name
    csoc_account_id      = local.csoc_account_id

    spokes          = local.spoke_configs
    provider_spokes = local.provider_spoke_configs

    allow_devcontainer_assume_role = local.allow_devcontainer_assume_role

    tags = local.base_tags
  }
}

unit "csoc_in_cluster_bootstrap" {
  source = "${local.units_path}/csoc-in-cluster-bootstrap"
  path   = "csoc-in-cluster-bootstrap"

  values = merge(local.foundation_values, {
    state_key = "csoc/in-cluster-bootstrap/terraform.tfstate"

    csoc_account_id      = local.csoc_account_id
    cluster_name         = local.cluster_name
    csoc_foundation_path = "../csoc-foundation"
    spoke_iam_path       = "../spoke-iam"

    ssm_repo_secret_names      = lookup(local.config, "ssm_repo_secret_names", {})
    argocd_cluster_secret_name = lookup(local.config, "argocd_cluster_secret_name", "")

    outputs_dir = "${local.repo_root}/outputs"
    stack_dir   = "${local.repo_root}/outputs"
  })
}
