# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the iam-spoke module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/iam-spoke?ref=${local.version}"
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
    cluster_info = {
      cluster_name = "mock-cluster"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks_hub" {
  config_path = "../eks-hub"

  mock_outputs = {
    ack_hub_roles = {
      iam = { arn = "arn:aws:iam::123456789012:role/mock-ack-iam" }
      ec2 = { arn = "arn:aws:iam::123456789012:role/mock-ack-ec2" }
      eks = { arn = "arn:aws:iam::123456789012:role/mock-ack-eks" }
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    ack_services = ["iam", "ec2", "eks"]

    alias_tag    = "spoke-1"
    spoke_alias  = "spoke-1"

    enable_external_spoke = false
    enable_internal_spoke = true

    cluster_info  = dependency.eks_cluster.outputs.cluster_info
    ack_hub_roles = dependency.eks_hub.outputs.ack_hub_roles
  }
)

