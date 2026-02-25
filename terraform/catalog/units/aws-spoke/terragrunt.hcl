###############################################################################
# AWS Spoke Unit — Multi-Spoke Aggregator (generate-based)
#
# Dynamically generates Terraform configuration (backend, versions, providers,
# main) for every entry in the `spokes` map passed from the stack. Each spoke
# receives its own AWS provider alias so cross-account profiles are isolated.
#
# Input values supplied by the stack (terragrunt.stack.hcl):
#   modules_path    — repo-relative path to terraform/catalog/modules
#   region          — default AWS region (used for the S3 backend)
#   state_bucket    — S3 bucket name
#   state_key       — S3 object key for this unit's terraform.tfstate
#   cluster_name    — CSOC EKS cluster name (for cross-account trust policy)
#   csoc_account_id — CSOC AWS account ID (for cross-account trust policy)
#   spokes          — map of alias → { profile, region, roles }
#   tags            — common resource tags applied to all IAM resources
###############################################################################

terraform {
  # The unit directory IS the Terraform root; all .tf files are generated.
  source = get_original_terragrunt_dir()
}

###############################################################################
# Backend — S3, no DynamoDB lock
###############################################################################
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

###############################################################################
# Versions — required providers declaration
###############################################################################
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

###############################################################################
# Providers — one aliased AWS provider per spoke
###############################################################################
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents = join("\n", [
    for alias, spoke_cfg in values.spokes : <<-EOT
      provider "aws" {
        alias   = "${alias}"
        profile = "${spoke_cfg.profile}"
        region  = "${spoke_cfg.region}"
      }
    EOT
  ])
}

###############################################################################
# Main — one module call per spoke, wired to its aliased provider
###############################################################################
generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents = join("\n", [
    for alias, spoke_cfg in values.spokes : <<-EOT
      module "aws_spoke_${replace(alias, "-", "_")}" {
        source          = "${get_repo_root()}/${values.modules_path}/aws-spoke"
        cluster_name    = "${values.cluster_name}"
        csoc_account_id = "${values.csoc_account_id}"
        spoke_alias     = "${alias}"
        roles           = ${jsonencode(spoke_cfg.roles)}
        tags            = ${jsonencode(values.tags)}
        providers = {
          aws = aws.${alias}
        }
      }
    EOT
  ])
}
