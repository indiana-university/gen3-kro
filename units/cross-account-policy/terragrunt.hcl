# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the cross-account-policy module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/cross-account-policy?ref=${local.version}"
}

# Locals
locals {
  # Load version from environment or default
  version = get_env("GEN3_KRO_VERSION", "main")

  # Load common configuration
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl", "empty.hcl"), { inputs = {} })

  # ACK service name
  service_name = get_env("ACK_SERVICE_NAME", "iam")

  # Spoke role ARNs - passed via environment as comma-separated list
  # Format: arn:aws:iam::111111111111:role/spoke1-ack-iam-spoke-role,arn:aws:iam::222222222222:role/spoke2-ack-iam-spoke-role
  spoke_role_arns_env = get_env("SPOKE_ROLE_ARNS", "")
  spoke_role_arns = local.spoke_role_arns_env != "" ? split(",", local.spoke_role_arns_env) : []
}

# Dependencies
dependency "ack_pod_identity" {
  config_path = "../ack-pod-identity"

  mock_outputs = {
    iam_role_arn  = "arn:aws:iam::123456789012:role/mock-ack-role"
    iam_role_name = "mock-ack-role"
    service_name  = "iam"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Inputs passed to the module
inputs = merge(
  try(local.common_vars.inputs, {}),
  {
    create       = true
    service_name = local.service_name

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = dependency.ack_pod_identity.outputs.iam_role_arn

    # Spoke role ARNs
    spoke_role_arns = local.spoke_role_arns

    # Tags
    tags = try(local.common_vars.inputs.tags, {})
  }
)
