terraform {
  source = get_original_terragrunt_dir()
}

dependency "spoke_access" {
  config_path = values.spoke_access_unit_path

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "state"]
  mock_outputs = {
    spoke_role_arns = values.spoke_role_arns
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

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
  }
}
EOF
}

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.cluster_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.profile}"
  }
}

data "terraform_remote_state" "controller_iam" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.controller_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.profile}"
  }
}

data "terraform_remote_state" "argocd_install" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.argocd_install_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.profile}"
  }
}

provider "aws" {
  profile = "${values.profile}"
  region  = "${values.region}"
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", "${values.region}", "--profile", "${values.profile}"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", "${values.region}", "--profile", "${values.profile}"]
    }
  }
}

module "gitops_bootstrap" {
  source = "${get_repo_root()}/${values.modules_path}/argocd-gitops-bootstrap"

  enabled                            = ${values.enabled}
  cluster_name                       = data.terraform_remote_state.cluster.outputs.cluster_name
  argocd_namespace                   = data.terraform_remote_state.argocd_install.outputs.argocd_namespace
  ssm_repo_secret_names              = ${jsonencode(values.ssm_repo_secret_names)}
  argocd_cluster_secret_name         = "${values.argocd_cluster_secret_name}"
  argocd_cluster_labels              = ${jsonencode(values.argocd_cluster_labels)}
  argocd_cluster_annotations         = ${jsonencode(values.argocd_cluster_annotations)}
  ack_self_managed_role_arn          = try(data.terraform_remote_state.controller_iam.outputs.ack_csoc_role_arn, "")
  spoke_account_ids                  = ${jsonencode(values.spoke_account_ids)}
  bootstrap_dependency_token         = join(",", [data.terraform_remote_state.argocd_install.outputs.install_ready_token, "${sha256(jsonencode(dependency.spoke_access.outputs.spoke_role_arns))}"])
}

output "git_repository_secret_names" {
  value = module.gitops_bootstrap.git_repository_secret_names
}

output "argocd_cluster_secret_name" {
  value = module.gitops_bootstrap.argocd_cluster_secret_name
}

output "bootstrap_applicationset_name" {
  value = module.gitops_bootstrap.bootstrap_applicationset_name
}
EOF
}
