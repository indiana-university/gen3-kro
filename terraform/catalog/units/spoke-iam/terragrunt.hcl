###############################################################################
# Spoke IAM Unit
#
# Creates per-spoke ACK workload roles after CSOC foundation exists. The exact
# CSOC source role ARN is read from the foundation dependency when available.
###############################################################################

terraform {
  source = get_original_terragrunt_dir()
}

dependency "csoc_foundation" {
  config_path = values.csoc_foundation_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    ack_csoc_role_arn = ""
    cluster_name      = values.cluster_name
    csoc_account_id   = values.csoc_account_id
  }
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      backend "s3" {
        bucket  = "${values.state_bucket}"
        key     = "${values.state_key}"
        region  = "${values.region}"
        profile = "${values.csoc_profile}"
        encrypt = true
      }
    }
  EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.3"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = ">= 5.0"
        }
      }
    }
  EOF
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents = join("\n", [
    for alias, spoke_cfg in values.provider_spokes : <<-EOT
      provider "aws" {
        alias   = "${alias}"
        profile = "${spoke_cfg.profile}"
        region  = "${spoke_cfg.region}"
      }
    EOT
  ])
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents = join("\n", concat(
    [
      <<-EOT
        locals {
          csoc_source_role_arn = "${try(coalesce(dependency.csoc_foundation.outputs.ack_csoc_role_arn, ""), "")}"
          csoc_account_id      = "${try(coalesce(dependency.csoc_foundation.outputs.csoc_account_id, values.csoc_account_id), values.csoc_account_id)}"
          cluster_name         = "${try(coalesce(dependency.csoc_foundation.outputs.cluster_name, values.cluster_name), values.cluster_name)}"
        }
      EOT
    ],
    [
      for alias, spoke_cfg in values.spokes : <<-EOT
        module "aws_spoke_${replace(alias, "-", "_")}" {
          source                        = "${get_repo_root()}/${values.modules_path}/aws-spoke"
          cluster_name                  = local.cluster_name
          csoc_account_id               = local.csoc_account_id
          csoc_source_role_arn          = local.csoc_source_role_arn
          allow_devcontainer_assume_role = ${values.allow_devcontainer_assume_role}
          spoke_alias                   = "${alias}"
          roles                         = ${jsonencode(spoke_cfg.roles)}
          tags                          = ${jsonencode(values.tags)}
          providers = {
            aws = aws.${alias}
          }
        }
      EOT
    ]
  ))
}
