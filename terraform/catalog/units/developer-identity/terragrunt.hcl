###############################################################################
# Developer Identity Unit — Terragrunt Configuration
#
# Creates the host-side developer identity resources:
#   - Virtual MFA device
#   - devcontainer IAM role (MFA-required trust policy)
#   - Inline role policy (from iam/developer-identity/<policy_filename>)
#   - IAM user inline policy (allow sts:AssumeRole to the devcontainer role)
#   - Output files: mfa-setup-instructions.txt, aws-config-snippet.ini
#
# Managed from: terragrunt/live/aws/iam-setup/
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/developer-identity"
}

###############################################################################
# Backend — S3, no DynamoDB lock
###############################################################################
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket  = "${values.state_bucket}"
    key     = "${values.state_key}"
    region  = "${values.region}"
    profile = "${values.profile}"
    encrypt = true
  }
}
EOF
}

###############################################################################
# Provider
###############################################################################
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  profile = "${values.profile}"
  region  = "${values.region}"
}

# local provider — writes output files (mfa-setup-instructions.txt, aws-config-snippet.ini)
provider "local" {}
EOF
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  aws_profile = values.profile
  region      = values.region

  iam_user_name = values.iam_user_name

  role_name                 = values.role_name
  role_max_session_duration = values.role_max_session_duration
  assume_requires_mfa       = values.assume_requires_mfa
  assume_principal_arns     = values.assume_principal_arns
  attach_user_policy        = values.attach_user_policy

  mfa_device_name    = values.mfa_device_name
  create_virtual_mfa = values.create_virtual_mfa

  policy_filename = values.policy_filename
  inline_policy   = values.inline_policy

  outputs_dir = values.outputs_dir

  tags = values.tags
}
