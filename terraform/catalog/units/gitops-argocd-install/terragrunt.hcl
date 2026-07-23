terraform {
  source = "${get_repo_root()}/${values.modules_path}//gitops-argocd-install"
}

dependency "cluster" {
  config_path = values.cluster_unit_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "state"]
  mock_outputs = {
    cluster_name                       = values.cluster_name
    cluster_endpoint                   = "https://example.invalid"
    cluster_certificate_authority_data = ""
  }
}

dependency "controller_iam" {
  config_path = values.controller_unit_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "state"]
  mock_outputs = {
    argocd_controller_role_arn = ""
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

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "kubernetes" {
  host                   = "${dependency.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode("${dependency.cluster.outputs.cluster_certificate_authority_data}")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", "${dependency.cluster.outputs.cluster_name}", "--region", "${values.region}", "--profile", "${values.profile}"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = "${dependency.cluster.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode("${dependency.cluster.outputs.cluster_certificate_authority_data}")
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", "${dependency.cluster.outputs.cluster_name}", "--region", "${values.region}", "--profile", "${values.profile}"]
    }
  }
}
EOF
}

inputs = {
  enabled                    = values.enabled
  csoc_account_id            = values.csoc_account_id
  argocd_namespace           = values.argocd_namespace
  argocd_chart_version       = values.argocd_chart_version
  argocd_chart_repository    = values.argocd_chart_repository
  argocd_values              = values.argocd_values
  enable_argocd_self_managed = values.enable_argocd_self_managed
  enable_argocd_capability   = values.enable_argocd_capability
  argocd_bootstrap_enabled   = values.argocd_bootstrap_enabled
  argocd_controller_role_arn = dependency.controller_iam.outputs.argocd_controller_role_arn
}
