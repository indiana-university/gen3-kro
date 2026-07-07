###############################################################################
# Prerequisite IAM Stack
#
# Creates only the developer identity prerequisites needed to obtain scoped
# devcontainer credentials. This stack intentionally does not include CSOC
# foundation, spoke IAM, or in-cluster bootstrap units.
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
  state_bucket    = lookup(local.config, "backend_bucket", "")

  spokes_config       = lookup(local.config, "spokes", [])
  dev_identity_config = lookup(local.config, "developer_identity", {})

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

  base_tags = merge(
    { Terraform = "true", ManagedBy = "terragrunt", Stack = "prereq-iam" },
    lookup(local.config, "tags", {})
  )
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
