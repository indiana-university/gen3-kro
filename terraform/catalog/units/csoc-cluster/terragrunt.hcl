terraform {
  source = "${get_repo_root()}/${values.modules_path}//aws-csoc-cluster"
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
  csoc_alias                               = values.csoc_alias
  vpc_cidr                                 = values.vpc_cidr
  availability_zones                       = values.availability_zones
  private_subnet_cidrs                     = values.private_subnet_cidrs
  public_subnet_cidrs                      = values.public_subnet_cidrs
  public_subnet_tags                       = values.public_subnet_tags
  private_subnet_tags                      = values.private_subnet_tags
  enable_nat_gateway                       = values.enable_nat_gateway
  single_nat_gateway                       = values.single_nat_gateway
  kubernetes_version                       = values.kubernetes_version
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = values.cluster_compute_config
  environment                              = values.environment
  tags                                     = values.tags
}
