# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the argocd-deploy module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/argocd-deploy?ref=${local.version}"
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
    cluster_name     = "mock-cluster"
    cluster_endpoint = "https://mock-endpoint.eks.amazonaws.com"
    cluster_info     = {
      cluster_name = "mock-cluster"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks_pod_identities" {
  config_path = "../eks-pod-identities"

  mock_outputs = {
    argocd_hub_role_arn = "arn:aws:iam::123456789012:role/mock-argocd"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    cluster_name = dependency.eks_cluster.outputs.cluster_name
    cluster_info = dependency.eks_cluster.outputs.cluster_info
  }
)

