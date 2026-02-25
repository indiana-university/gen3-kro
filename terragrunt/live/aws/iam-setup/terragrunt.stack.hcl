###############################################################################
# IAM Setup Stack — Terragrunt Stack Configuration
#
# Manages all host-side IAM roles from a single stack:
#   1. developer-identity — virtual MFA device + devcontainer assume-role
#   2. aws-spoke          — ACK workload IAM roles for all enabled spokes
#
# Source of truth: config/shared.auto.tfvars.json
# Backend: S3 (no DynamoDB lock table)
# State key prefix: iam-setup/
###############################################################################

locals {
  repo_root = get_repo_root()

  modules_path = "terraform/catalog/modules"
  units_path   = "${get_repo_root()}/terraform/catalog/units"

  ###############################################################################
  # Configuration — read shared.auto.tfvars.json (single source of truth)
  ###############################################################################
  config_file = "${local.repo_root}/config/shared.auto.tfvars.json"
  config      = jsondecode(file(local.config_file))

  spokes_config        = lookup(local.config, "spokes", [])
  dev_identity_config  = lookup(local.config, "developer_identity", {})

  ###############################################################################
  # CSOC provider — shared AWS identity for CSOC account operations
  ###############################################################################
  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "cluster_name", "csoc")

  cluster_name = lookup(local.config, "cluster_name", "")

  ###############################################################################
  # Backend — S3 only, no DynamoDB lock
  ###############################################################################
  state_bucket = lookup(local.config, "backend_bucket", "")

  ###############################################################################
  # Spoke configuration — IAM role definitions from local policy files
  ###############################################################################
  spokes = [
    for spoke in local.spokes_config :
    spoke if lookup(spoke, "enabled", false)
  ]

  iam_base_path   = lookup(local.config, "iam_base_path", "iam")
  iam_policy_file = "inline-policy.json"

  # Load per-spoke ACK inline policy from iam/<spoke-alias>/ack/ with _default fallback
  spoke_ack_policy_documents = {
    for spoke in local.spokes :
    spoke.alias => try(
      jsondecode(file("${local.repo_root}/${local.iam_base_path}/${spoke.alias}/ack/${local.iam_policy_file}")),
      jsondecode(file("${local.repo_root}/${local.iam_base_path}/_default/ack/${local.iam_policy_file}")),
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

  spoke_ack_enabled = {
    for spoke_alias, policy_source in local.spoke_ack_policy_sources :
    spoke_alias => policy_source != "none"
  }

  spoke_ack_roles = {
    for spoke_alias, enabled in local.spoke_ack_enabled :
    spoke_alias => (
      enabled ? {
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

  # Spoke configs map — alias → { profile, region, roles } — passed to aws_spoke unit
  spoke_configs = {
    for spoke in local.spokes : spoke.alias => {
      profile = try(lookup(lookup(spoke, "provider", {}), "aws_profile", local.profile), local.profile)
      region  = try(lookup(lookup(spoke, "provider", {}), "region", local.region), local.region)
      roles   = lookup(local.spoke_ack_roles, spoke.alias, {})
    }
  }

  ###############################################################################
  # Developer identity configuration — sourced from developer_identity in shared.auto.tfvars.json
  ###############################################################################
  dev_iam_user_name         = lookup(local.dev_identity_config, "iam_user_name", "")
  dev_role_name             = lookup(local.dev_identity_config, "role_name", "eks-cluster-mgmt-devcontainer")
  dev_mfa_device_name       = lookup(local.dev_identity_config, "mfa_device_name", "eks-cluster-mgmt-virtual-mfa")
  dev_create_virtual_mfa    = lookup(local.dev_identity_config, "create_virtual_mfa", true)
  dev_assume_requires_mfa   = lookup(local.dev_identity_config, "assume_requires_mfa", true)
  dev_attach_user_policy    = lookup(local.dev_identity_config, "attach_user_policy", true)
  dev_policy_filename       = lookup(local.dev_identity_config, "policy_filename", "gen3-test-developer.json")
  dev_role_max_session_secs = lookup(local.dev_identity_config, "role_max_session_duration", 43200)

  ###############################################################################
  # Tags
  ###############################################################################
  base_tags = merge(
    { Terraform = "true", ManagedBy = "terragrunt" },
    lookup(local.config, "tags", {})
  )
}

###############################################################################
# Unit: developer-identity
# Creates the virtual MFA device and scoped devcontainer IAM role in the
# CSOC account. Output files are written to outputs/ in the repo root.
###############################################################################
unit "developer_identity" {
  source = "${local.units_path}/developer-identity"
  path   = "developer-identity"

  values = {
    modules_path = local.modules_path

    # AWS identity — uses CSOC provider (developer-identity lives in CSOC account)
    profile = local.profile
    region  = local.region

    # Backend — S3 only, no DynamoDB
    state_bucket = local.state_bucket
    state_key    = "iam-setup/developer-identity/terraform.tfstate"

    # IAM user config
    iam_user_name = local.dev_iam_user_name

    # Role config
    role_name                 = local.dev_role_name
    role_max_session_duration = local.dev_role_max_session_secs
    assume_requires_mfa       = local.dev_assume_requires_mfa
    assume_principal_arns     = []
    attach_user_policy        = local.dev_attach_user_policy

    # MFA device
    mfa_device_name    = local.dev_mfa_device_name
    create_virtual_mfa = local.dev_create_virtual_mfa

    # Policy — rendered at stack-eval time so module gets a fully-substituted
    # policy (account_id/region placeholders resolved). The module's own
    # templatefile() path doesn't resolve from the Terragrunt working copy.
    policy_filename = local.dev_policy_filename
    inline_policy   = templatefile("${local.repo_root}/iam/developer-identity/${local.dev_policy_filename}", {
      account_id = local.csoc_account_id
      region     = local.region
    })

    # Output files land in <repo-root>/outputs/
    outputs_dir = "${local.repo_root}/outputs"

    tags = local.base_tags
  }
}

###############################################################################
# Unit: aws-spoke
# Creates ACK workload IAM roles for ALL enabled spokes in a single state.
# The unit generates one module call per spoke via Terragrunt `generate` blocks.
# State: iam-setup/aws-spoke/terraform.tfstate
###############################################################################
unit "aws_spoke" {
  source = "${local.units_path}/aws-spoke"
  path   = "aws-spoke"

  values = {
    modules_path = local.modules_path

    # Backend — S3 only, no DynamoDB
    state_bucket = local.state_bucket
    state_key    = "iam-setup/aws-spoke/terraform.tfstate"

    # Default region and profile for S3 backend auth
    region       = local.region
    csoc_profile = local.profile

    # Cross-account trust metadata
    cluster_name    = local.cluster_name
    csoc_account_id = local.csoc_account_id

    # All enabled spokes — alias → { profile, region, roles }
    spokes = local.spoke_configs

    tags = local.base_tags
  }
}
