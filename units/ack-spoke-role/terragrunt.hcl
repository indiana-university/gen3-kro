# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the ack-spoke-role module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/ack-spoke-role?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })

  # ACK service name and spoke alias
  service_name = get_env("ACK_SERVICE_NAME", "iam")
  spoke_alias  = get_env("SPOKE_ALIAS", "spoke1")
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
    combined_policy_json  = null
    policy_arns           = {}
    has_inline_policy     = false
    has_managed_policy    = false
    service_name          = "iam"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "ack_pod_identity" {
  config_path = "../ack-pod-identity"

  mock_outputs = {
    iam_role_arn = "arn:aws:iam::123456789012:role/mock-ack-role"
    service_name = "iam"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Generate spoke provider configuration
generate "provider_spoke" {
  path      = "provider_spoke.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias  = "spoke"
      region = "${get_env("AWS_REGION", "us-east-1")}"

      # Assume role in spoke account if specified
      assume_role {
        role_arn = "${get_env("SPOKE_ROLE_ARN", "")}"
      }
    }
  EOF
}

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    create       = true
    cluster_name = dependency.eks_cluster.outputs.cluster_name
    service_name = dependency.ack_iam_policy.outputs.service_name
    spoke_alias  = local.spoke_alias

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = dependency.ack_pod_identity.outputs.iam_role_arn

    # Policy inputs from ack-iam-policy module
    combined_policy_json = dependency.ack_iam_policy.outputs.combined_policy_json
    policy_arns          = dependency.ack_iam_policy.outputs.policy_arns
    has_inline_policy    = dependency.ack_iam_policy.outputs.has_inline_policy
    has_managed_policy   = dependency.ack_iam_policy.outputs.has_managed_policy

    # Tags
    tags = try(local.common_vars.inputs.tags, {})
  }
)
