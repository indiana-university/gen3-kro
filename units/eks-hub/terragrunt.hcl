# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the eks-hub module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/eks-hub?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })
}

# Dependencies
dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    create       = true
    cluster_name = dependency.eks_cluster.outputs.cluster_name
    hub_alias    = "hub"

    ack_services = ["iam", "ec2", "eks"]

    user_provided_inline_policy_link = ""
  }
)

