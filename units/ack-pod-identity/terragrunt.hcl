# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the ack-pod-identity module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/ack-pod-identity?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })

  # ACK service name - this should be set in stack or passed as input
  service_name = get_env("ACK_SERVICE_NAME", "iam")
}

# Dependencies
dependency "eks_cluster" {
  config_path = "../eks-cluster"

  mock_outputs = {
    cluster_name = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "ack_iam_policy" {
  config_path = "../ack-iam-policy"

  mock_outputs = {
    source_policy_documents   = []
    override_policy_documents = []
    policy_arns               = {}
    has_inline_policy         = false
    service_name              = "iam"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    create       = true
    cluster_name = dependency.eks_cluster.outputs.cluster_name
    service_name = dependency.ack_iam_policy.outputs.service_name

    # Policy inputs from ack-iam-policy module
    source_policy_documents   = dependency.ack_iam_policy.outputs.source_policy_documents
    override_policy_documents = dependency.ack_iam_policy.outputs.override_policy_documents
    policy_arns               = dependency.ack_iam_policy.outputs.policy_arns
    has_inline_policy         = dependency.ack_iam_policy.outputs.has_inline_policy

    # Pod Identity Association configuration
    association_defaults = {
      namespace = "ack-system"
    }

    associations = {
      controller = {
        cluster_name    = dependency.eks_cluster.outputs.cluster_name
        service_account = "ack-${local.service_name}-controller"
      }
    }

    # Trust policy conditions
    trust_policy_conditions = []

    # Tags
    tags = try(local.common_vars.inputs.tags, {})
  }
)
