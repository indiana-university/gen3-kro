# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Locals
inputs {
  # Load version from environment or default
  version = values.version

  # VPC-specific configuration
  vpc_config = {
    vpc_name           = values.vpc_name
    vpc_cidr           = values.vpc_cidr
    cluster_name       = values.cluster_name
    enable_nat_gateway = values.enable_nat_gateway
    single_nat_gateway = values.single_nat_gateway
  }
}

# Point to the vpc module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/vpc?ref=${local.version}"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region  = "${local.hub.aws_region}"
      profile = "${local.hub.aws_profile}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }
  EOF
}

