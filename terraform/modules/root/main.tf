###################################################################################################################################################
# Hub Cluster Modules
###################################################################################################################################################
module "kind-hub" {
  source = "../kind-hub"
  create             = (var.environment == "dev" || var.environment == "staging") ? true : false
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  kubeconfig_dir     = var.kubeconfig_dir
}

module "eks-hub" {
  source = "../eks-hub"

  create                       = var.environment == "prod" ? true : false
  aws_region                   = var.hub_aws_region
  vpc_name                     = local.vpc_name
  cluster_name                 = local.cluster_name
  cluster_info                 = local.cluster_info
  vpc_cidr                     = local.vpc_cidr
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

  create  = local.oss_addons.enable_argocd
  cluster = local.argocd_cluster_data
  apps    = local.argocd_apps
  argocd  = local.argocd_settings

  depends_on = [module.kind-hub, module.eks-hub]
}

###################################################################################################################################################
# External Secrets Operator Bootstrap (Compulsory for private repo access)
###################################################################################################################################################
# module "eso_bootstrap-kind" {
#   source = "../eso-bootstrap"

#   create           = local.aws_addons.enable_external_secrets && (var.environment == "dev" || var.environment == "staging") ? true : false
#   namespace        = local.external_secrets.namespace
#   argocd_namespace = local.argocd_namespace
#   service_account  = local.external_secrets.service_account
#   aws_region       = var.hub_aws_region
#   cluster_name     = local.cluster_name
#   repos            = local.gitops_private_repos

#   depends_on = [module.kind-hub, module.eks-hub]
# }

# module "eso_bootstrap-eks" {
#   source = "../eso-bootstrap"

#   create           = local.aws_addons.enable_external_secrets && (var.environment == "prod" ? true : false)
#   namespace        = local.external_secrets.namespace
#   argocd_namespace = local.argocd_namespace
#   service_account  = local.external_secrets.service_account
#   aws_region       = var.hub_aws_region
#   cluster_name     = local.cluster_name
#   repos            = local.gitops_private_repos

#   depends_on = [module.kind-hub, module.eks-hub]
# }

###################################################################################################################################################
# End of File
###################################################################################################################################################