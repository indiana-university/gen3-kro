###############################################################################
# CSOC Foundation Unit
#
# Creates AWS-only CSOC foundation resources:
#   - VPC and EKS cluster
#   - EKS OIDC provider
#   - CSOC ACK source role and Argo CD IAM role
#   - Optional AWS-managed EKS capabilities
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/aws-csoc-foundation"
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
  aws_profile       = values.profile
  spoke_account_ids = values.spoke_account_ids

  csoc_alias           = values.csoc_alias
  vpc_cidr             = values.vpc_cidr
  availability_zones   = values.availability_zones
  private_subnet_cidrs = values.private_subnet_cidrs
  public_subnet_cidrs  = values.public_subnet_cidrs
  public_subnet_tags   = values.public_subnet_tags
  private_subnet_tags  = values.private_subnet_tags
  enable_nat_gateway   = values.enable_nat_gateway
  single_nat_gateway   = values.single_nat_gateway

  kubernetes_version                       = values.kubernetes_version
  environment                              = values.environment
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = values.cluster_compute_config
  enable_automode                          = values.enable_automode
  enable_efs                               = values.enable_efs

  argocd_namespace        = values.argocd_namespace
  argocd_chart_version    = values.argocd_chart_version
  argocd_chart_repository = values.argocd_chart_repository
  argocd_values           = values.argocd_values

  external_secrets_namespace       = values.external_secrets_namespace
  external_secrets_service_account = values.external_secrets_service_account

  addons = values.addons

  argocd_bootstrap_enabled = values.argocd_bootstrap_enabled

  ack_management_type        = values.ack_management_type
  kro_management_type        = values.kro_management_type
  argocd_management_type     = values.argocd_management_type
  enable_ack_capability      = values.enable_ack_capability
  enable_kro_capability      = values.enable_kro_capability
  enable_argocd_capability   = values.enable_argocd_capability
  enable_ack_self_managed    = values.enable_ack_self_managed
  enable_argocd_self_managed = values.enable_argocd_self_managed
  ack_namespace              = values.ack_namespace
  use_ack                    = values.use_ack

  git_org_name                 = values.git_org_name
  gitops_addons_repo_name      = values.gitops_addons_repo_name
  gitops_addons_repo_path      = values.gitops_addons_repo_path
  gitops_addons_repo_base_path = values.gitops_addons_repo_base_path
  gitops_addons_repo_revision  = values.gitops_addons_repo_revision
  gitops_addons_github_url     = values.gitops_addons_github_url
  gitops_addons_org_name       = values.gitops_addons_org_name

  gitops_fleet_repo_name      = values.gitops_fleet_repo_name
  gitops_fleet_repo_path      = values.gitops_fleet_repo_path
  gitops_fleet_repo_base_path = values.gitops_fleet_repo_base_path
  gitops_fleet_repo_revision  = values.gitops_fleet_repo_revision
  gitops_fleet_github_url     = values.gitops_fleet_github_url
  gitops_fleet_org_name       = values.gitops_fleet_org_name

  tags = values.tags
}
