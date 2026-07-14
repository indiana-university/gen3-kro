terraform {
  source = "${get_repo_root()}/${values.modules_path}//aws-csoc-controller-iam"
}

dependency "cluster" {
  config_path = values.cluster_unit_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "state"]
  mock_outputs = {
    cluster_name            = values.cluster_name
    cluster_oidc_issuer_url = "https://oidc.eks.${values.region}.amazonaws.com/id/mock"
    oidc_provider_arn       = "arn:aws:iam::${values.csoc_account_id}:oidc-provider/oidc.eks.${values.region}.amazonaws.com/id/mock"
  }
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  backend "s3" {
    bucket       = "${values.state_bucket}"
    key          = "${values.state_key}"
    region       = "${values.backend_region}"
    profile      = "${values.profile}"
    encrypt      = true
    use_lockfile = true
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
  csoc_alias                       = values.csoc_alias
  cluster_name                     = dependency.cluster.outputs.cluster_name
  cluster_oidc_issuer_url          = dependency.cluster.outputs.cluster_oidc_issuer_url
  oidc_provider_arn                = dependency.cluster.outputs.oidc_provider_arn
  argocd_namespace                 = values.argocd_namespace
  ack_namespace                    = values.ack_namespace
  external_secrets_namespace       = values.external_secrets_namespace
  external_secrets_service_account = values.external_secrets_service_account
  addons                           = values.addons
  ack_management_type              = values.ack_management_type
  kro_management_type              = values.kro_management_type
  argocd_management_type           = values.argocd_management_type
  enable_ack_capability            = values.enable_ack_capability
  enable_kro_capability            = values.enable_kro_capability
  enable_argocd_capability         = values.enable_argocd_capability
  enable_ack_self_managed          = values.enable_ack_self_managed
  enable_argocd_self_managed       = values.enable_argocd_self_managed
  environment                      = values.environment
  tags                             = values.tags
}
