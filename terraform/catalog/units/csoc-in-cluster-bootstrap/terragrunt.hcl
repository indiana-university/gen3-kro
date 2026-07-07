###############################################################################
# CSOC In-Cluster Bootstrap Unit
#
# Installs or targets Argo CD on an existing named CSOC cluster, creates repo and
# cluster secrets, and seeds the first bootstrap ApplicationSet.
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/csoc-in-cluster-bootstrap"
}

dependency "csoc_foundation" {
  config_path = values.csoc_foundation_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs = {
    ack_csoc_role_arn                  = ""
    argocd_cluster_annotations_base    = {}
    argocd_cluster_labels_base         = {}
    argocd_namespace                   = values.argocd_namespace
    argocd_self_managed_role_arn       = ""
    cluster_certificate_authority_data = "bW9jay1jYQ=="
    cluster_endpoint                   = "https://example.invalid"
    cluster_name                       = values.cluster_name
    csoc_account_id                    = values.csoc_account_id
    foundation_ready_token             = "mock-foundation"
    spoke_account_ids                  = values.spoke_account_ids
  }
}

dependency "spoke_iam" {
  config_path = values.spoke_iam_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
  mock_outputs                            = {}
}

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

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  profile = "${values.profile}"
  region  = "${values.region}"
}
EOF
}

inputs = {
  enabled = values.argocd_bootstrap_enabled || values.enable_argocd_self_managed || values.enable_argocd_capability

  aws_profile                        = values.profile
  region                             = values.region
  cluster_name                       = dependency.csoc_foundation.outputs.cluster_name
  cluster_endpoint                   = dependency.csoc_foundation.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.csoc_foundation.outputs.cluster_certificate_authority_data
  foundation_dependency_token        = dependency.csoc_foundation.outputs.foundation_ready_token
  csoc_account_id                    = dependency.csoc_foundation.outputs.csoc_account_id

  argocd_namespace             = dependency.csoc_foundation.outputs.argocd_namespace
  argocd_chart_version         = values.argocd_chart_version
  argocd_chart_repository      = values.argocd_chart_repository
  argocd_values                = values.argocd_values
  enable_argocd_self_managed   = values.enable_argocd_self_managed
  enable_argocd_capability     = values.enable_argocd_capability
  argocd_self_managed_role_arn = dependency.csoc_foundation.outputs.argocd_self_managed_role_arn
  argocd_bootstrap_enabled     = values.argocd_bootstrap_enabled

  ssm_repo_secret_names      = values.ssm_repo_secret_names
  argocd_cluster_secret_name = values.argocd_cluster_secret_name
  argocd_cluster_labels      = dependency.csoc_foundation.outputs.argocd_cluster_labels_base
  argocd_cluster_annotations = dependency.csoc_foundation.outputs.argocd_cluster_annotations_base
  ack_self_managed_role_arn  = dependency.csoc_foundation.outputs.ack_csoc_role_arn
  spoke_account_ids          = values.spoke_account_ids

  outputs_dir = values.outputs_dir
  stack_dir   = values.stack_dir
}
