# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the eks-cluster module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/eks-cluster?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })
}

# Dependencies
dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock-12345"
    private_subnets = ["subnet-mock-1", "subnet-mock-2", "subnet-mock-3"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    cluster_name    = "hub-cluster"
    cluster_version = "1.31"
    vpc_id          = dependency.vpc.outputs.vpc_id
    subnet_ids      = dependency.vpc.outputs.private_subnets

    cluster_endpoint_public_access           = true
    enable_cluster_creator_admin_permissions = true

    cluster_compute_config = {
      enabled    = true
      node_pools = ["general-purpose", "system"]
    }
  }
)
