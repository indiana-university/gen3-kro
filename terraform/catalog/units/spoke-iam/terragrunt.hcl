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
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

module "spoke" {
  source = "${get_repo_root()}/${values.modules_path}/aws-spoke-iam"

  cluster_name                   = "${values.cluster_name}"
  csoc_account_id                = "${values.csoc_account_id}"
  csoc_source_role_arn           = data.terraform_remote_state.controller_iam.outputs.ack_csoc_role_arn
  allow_devcontainer_assume_role = ${values.allow_devcontainer_assume_role}
  spoke_alias                    = "${values.spoke_alias}"
  roles                          = ${jsonencode(values.roles)}
  tags                           = ${jsonencode(values.tags)}
}

output "spoke_alias" {
  value = module.spoke.spoke_alias
}

output "account_id" {
  value = module.spoke.account_id
}

output "role_arns" {
  value = module.spoke.role_arns
}

output "role_names" {
  value = module.spoke.role_names
}

output "primary_role_arn" {
  value = try(module.spoke.role_arns["ack-controller"], "")
}

output "trust_mode" {
  value = module.spoke.trust_mode
}
EOF
}
