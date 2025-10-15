# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Point to the ack-iam-policy module
terraform {
  source = "git::git@github.com:indiana-university/gen3-kro.git//modules/ack-iam-policy?ref=${local.version}"
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

# Inputs passed to the module
inputs = merge(
  local.common_vars.inputs,
  {
    create       = true
    service_name = local.service_name
    
    # Override policy path (e.g., /iam/pod-identities/iam.json)
    override_policy_path = "${get_repo_root()}/iam/pod-identities/${local.service_name}.json"
    
    # Alternative: Use URL for override policy
    # override_policy_url = "https://example.com/policies/${local.service_name}.json"
    
    # Additional managed policy ARNs if needed
    additional_policy_arns = {}
  }
)
