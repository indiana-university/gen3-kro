terraform {
  source = get_original_terragrunt_dir()
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
  required_version = ">= 1.15.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.55.0"
    }
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

generate "main" {
  path      = "main.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "terraform_remote_state" "operator_iam" {
  backend = "s3"
  config = {
    bucket  = "${values.state_bucket}"
    key     = "${values.operator_state_key}"
    region  = "${values.backend_region}"
    profile = "${values.profile}"
  }
}

module "aws_csoc_cluster" {
  source = "${get_repo_root()}/${values.modules_path}/aws-csoc-cluster"

  csoc_alias                               = "${values.csoc_alias}"
  vpc_cidr                                 = "${values.vpc_cidr}"
  availability_zones                       = ${jsonencode(values.availability_zones)}
  private_subnet_cidrs                     = ${jsonencode(values.private_subnet_cidrs)}
  public_subnet_cidrs                      = ${jsonencode(values.public_subnet_cidrs)}
  public_subnet_tags                       = ${jsonencode(values.public_subnet_tags)}
  private_subnet_tags                      = ${jsonencode(values.private_subnet_tags)}
  enable_nat_gateway                       = ${values.enable_nat_gateway}
  single_nat_gateway                       = ${values.single_nat_gateway}
  kubernetes_version                       = "${values.kubernetes_version}"
  cluster_endpoint_public_access           = ${values.cluster_endpoint_public_access}
  enable_cluster_creator_admin_permissions = ${values.enable_cluster_creator_admin_permissions}
  cluster_compute_config                   = ${jsonencode(values.cluster_compute_config)}
  operator_access_entries                  = try(data.terraform_remote_state.operator_iam.outputs.eks_access_entries, {})
  environment                              = "${values.environment}"
  tags                                     = ${jsonencode(values.tags)}
}

output "cluster_name" {
  value = module.aws_csoc_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.aws_csoc_cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.aws_csoc_cluster.cluster_certificate_authority_data
  sensitive = true
}

output "cluster_oidc_issuer_url" {
  value = module.aws_csoc_cluster.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  value = module.aws_csoc_cluster.oidc_provider_arn
}

output "vpc_id" {
  value = module.aws_csoc_cluster.vpc_id
}

output "private_subnet_ids" {
  value = module.aws_csoc_cluster.private_subnet_ids
}

output "cluster_ready_token" {
  value = module.aws_csoc_cluster.cluster_ready_token
}
EOF
}
