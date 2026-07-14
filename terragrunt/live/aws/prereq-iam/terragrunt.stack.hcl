locals {
  repo_root    = get_repo_root()
  modules_path = "terraform/catalog/modules"
  units_path   = "${local.repo_root}/terraform/catalog/units"
  config       = jsondecode(file("${local.repo_root}/config/shared.auto.tfvars.json"))

  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "csoc_alias", "csoc")
  state_bucket    = lookup(local.config, "backend_bucket", "")
  backend_region  = lookup(local.config, "backend_region", local.region)

  spokes          = lookup(local.config, "spokes", [])
  operator_config = lookup(local.config, "developer_identity", {})

  iam_user_name        = lookup(local.operator_config, "iam_user_name", "")
  role_name            = "${local.csoc_alias}-${lookup(local.operator_config, "devcontainer_role_suffix", "devcontainer-role")}"
  mfa_device_name      = "${local.csoc_alias}-${lookup(local.operator_config, "mfa_device_suffix", "devcontainer-mfa")}"
  create_virtual_mfa   = lookup(local.operator_config, "create_virtual_mfa", true)
  assume_requires_mfa  = lookup(local.operator_config, "assume_requires_mfa", true)
  attach_user_policy   = lookup(local.operator_config, "attach_user_policy", true)
  policy_filename      = lookup(local.operator_config, "policy_filename", "gen3-test-developer.json")
  max_session_duration = lookup(local.operator_config, "role_max_session_duration", 43200)
  tags                 = merge({ Terraform = "true", ManagedBy = "terragrunt" }, lookup(local.config, "tags", {}))
}

unit "operator_access" {
  source = "${local.units_path}/operator-access"
  path   = "operator-access"

  values = {
    modules_path = local.modules_path
    profile      = local.profile
    region       = local.region

    state_bucket   = local.state_bucket
    backend_region = local.backend_region
    state_key      = "prereq/operator-access/terraform.tfstate"

    iam_user_name             = local.iam_user_name
    devcontainer_role_name    = local.role_name
    role_max_session_duration = local.max_session_duration
    assume_requires_mfa       = local.assume_requires_mfa
    assume_principal_arns     = []
    attach_user_policy        = local.attach_user_policy
    mfa_device_name           = local.mfa_device_name
    create_virtual_mfa        = local.create_virtual_mfa
    policy_filename           = local.policy_filename
    inline_policy = templatefile("${local.repo_root}/iam/developer-identity/${local.policy_filename}", merge(
      { account_id = local.csoc_account_id, region = local.region },
      { for spoke in local.spokes : "${spoke.alias}_account_id" => lookup(lookup(spoke, "provider", {}), "account_id", local.csoc_account_id) }
    ))
    outputs_dir = "${local.repo_root}/outputs"
    tags        = local.tags
  }
}
