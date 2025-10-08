###################################################################################################################################################
# Hub Cluster Modules
###################################################################################################################################################
# Kind module removed - EKS-only infrastructure
# All environments now use EKS

module "eks-hub" {
  source = "../eks-hub"

  create                       = true  # Always create EKS cluster
  aws_region                   = var.hub_aws_region
  ack_services                 = var.ack_services
  ack_services_config          = local.ack_services_config
  vpc_name                     = local.vpc_name
  cluster_name                 = local.cluster_name
  cluster_info                 = local.cluster_info
  vpc_cidr                     = local.vpc_cidr
  hub_alias                    = var.hub_alias
  azs                          = local.azs
  cluster_version              = local.cluster_version
  aws_addons                   = local.aws_addons
  oss_addons                   = local.oss_addons
  external_secrets             = local.external_secrets
  aws_load_balancer_controller = local.aws_load_balancer_controller
  tags                         = local.tags

  providers = {
    aws        = aws.hub
  }
}

###################################################################################################################################################
# GitOps Bridge and ArgoCD Bootstrap
###################################################################################################################################################
module "gitops-bridge-bootstrap" {
  source = "../argocd-bootstrap"

  create      = local.oss_addons.enable_argocd
  cluster     = local.argocd_cluster_data
  apps        = local.argocd_apps
  argocd      = local.argocd_settings
  outputs_dir = var.outputs_dir

  depends_on = [module.eks-hub]
}

###################################################################################################################################################
# IAM Access is now defined in iam-access.tf (inline in root module for dynamic provider support)
###################################################################################################################################################

###################################################################################################################################################
# End of File
###################################################################################################################################################
