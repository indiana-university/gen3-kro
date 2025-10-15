# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the vpc module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/vpc?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })

  # VPC-specific configuration
  vpc_config = {
    vpc_name           = "gen3-vpc"
    vpc_cidr           = "10.0.0.0/16"
    cluster_name       = "hub-cluster"
    enable_nat_gateway = true
    single_nat_gateway = true
  }
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  local.vpc_config,
  {
    # Override with stack-specific values if needed
  }
)
