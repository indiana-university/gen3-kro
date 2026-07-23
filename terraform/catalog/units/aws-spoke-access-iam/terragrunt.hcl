terraform {
  source = get_original_terragrunt_dir()
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
    profile      = "${values.backend_profile}"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.15.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.55.0"
    }
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  profile = "${values.spoke_profile}"
  region  = "${values.spoke_region}"
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
    profile = "${values.backend_profile}"
  }
}

data "terraform_remote_state" "operator_iam" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.operator_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.backend_profile}"
  }
}

module "aws_spoke_access_iam" {
  source = "${get_repo_root()}/${values.modules_path}/aws-spoke-access-iam"

  cluster_name                 = "${values.cluster_name}"
  csoc_source_role_arn         = data.terraform_remote_state.controller_iam.outputs.ack_controller_role_arn
  manual_operator_role_arns    = try(toset(data.terraform_remote_state.operator_iam.outputs.spoke_access_role_arns), [])
  spoke_alias                  = "${values.spoke_alias}"
  roles                        = ${jsonencode(values.roles)}
  tags                         = ${jsonencode(values.tags)}
}

output "spoke_alias" {
  value = module.aws_spoke_access_iam.spoke_alias
}

output "account_id" {
  value = module.aws_spoke_access_iam.account_id
}

output "role_arns" {
  value = module.aws_spoke_access_iam.role_arns
}

output "role_names" {
  value = module.aws_spoke_access_iam.role_names
}

output "ack_controller_access_role_arn" {
  value = try(module.aws_spoke_access_iam.role_arns["ack-controller"], "")
}

output "trust_mode" {
  value = module.aws_spoke_access_iam.trust_mode
}
EOF
}
