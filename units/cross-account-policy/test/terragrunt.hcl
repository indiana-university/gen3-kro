# Test Configuration for cross-account-policy Unit
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules//cross-account-policy"
}

locals {
  service_name = "ec2"
  spoke_role_arns = [
    "arn:aws:iam::111111111111:role/spoke1-ack-ec2-spoke-role",
    "arn:aws:iam::222222222222:role/spoke2-ack-ec2-spoke-role",
    "arn:aws:iam::333333333333:role/spoke3-ack-ec2-spoke-role"
  ]
}

inputs = {
  create                    = true
  service_name              = local.service_name
  hub_pod_identity_role_arn = "arn:aws:iam::123456789012:role/test-cluster-ack-${local.service_name}"
  spoke_role_arns          = local.spoke_role_arns
  tags = {
    Environment = "test"
    ManagedBy   = "terragrunt"
  }
}
