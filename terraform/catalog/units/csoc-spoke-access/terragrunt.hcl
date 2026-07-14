terraform {
  source = get_original_terragrunt_dir()
}

dependency "selected_spoke" {
  config_path = values.spoke_unit_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "state"]
  mock_outputs = {
    primary_role_arn = values.selected_spoke_role_arn
  }
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
EOF
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "terraform_remote_state" "controller_iam" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.controller_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.profile}"
  }
}

module "spoke_access" {
  source = "${get_repo_root()}/${values.modules_path}/aws-csoc-spoke-access"

  source_role_name = data.terraform_remote_state.controller_iam.outputs.ack_csoc_role_name
  spoke_role_arns  = ${jsonencode(merge(values.spoke_role_arns, { (values.selected_spoke_alias) = dependency.selected_spoke.outputs.primary_role_arn }))}
  policy_name      = "${values.policy_name}"
}

output "spoke_role_arns" {
  value = module.spoke_access.spoke_role_arns
}
EOF
}
