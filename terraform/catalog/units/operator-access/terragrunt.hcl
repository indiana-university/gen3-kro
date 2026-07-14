terraform {
  source = "${get_repo_root()}/${values.modules_path}//aws-operator-access-iam"
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket       = "${values.state_bucket}"
    key          = "${values.state_key}"
    region       = "${values.backend_region}"
    profile      = "${values.profile}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  profile = "${values.profile}"
  region  = "${values.region}"
}

provider "local" {}
EOF
}

inputs = {
  aws_profile               = values.profile
  region                    = values.region
  iam_user_name             = values.iam_user_name
  devcontainer_role_name    = values.devcontainer_role_name
  role_max_session_duration = values.role_max_session_duration
  assume_requires_mfa       = values.assume_requires_mfa
  assume_principal_arns     = values.assume_principal_arns
  attach_user_policy        = values.attach_user_policy
  mfa_device_name           = values.mfa_device_name
  create_virtual_mfa        = values.create_virtual_mfa
  policy_filename           = values.policy_filename
  inline_policy             = values.inline_policy
  outputs_dir               = values.outputs_dir
  tags                      = values.tags
}
