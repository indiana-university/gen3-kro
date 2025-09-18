################################################################################
# Hub Cluster Modules
################################################################################
module "kind-hub" {
  source = "../kind-hub"

  cluster_name       = var.environment == "dev" || var.environment == "staging" ? var.cluster_name       : null
  kubernetes_version = var.environment == "dev" || var.environment == "staging" ? var.kubernetes_version : null
  kubeconfig_dir     = var.environment == "dev" || var.environment == "staging" ? var.kubeconfig_dir     : null

  providers = {
    kubernetes = kubernetes.local
    helm       = helm.local
  }
}

module "eks-hub" {
  source = "../eks-hub"

  aws_region                   = var.hub_aws_region
  enable_eks_hub               = local.enable_eks_hub
  vpc_name                     = local.vpc_name
  cluster_name                 = local.cluster_name
  vpc_cidr                     = local.vpc_cidr
  azs                          = local.azs
  cluster_version              = local.cluster_version
  aws_addons                   = local.aws_addons
  external_secrets             = local.external_secrets
  aws_load_balancer_controller = local.aws_load_balancer_controller
  tags                         = local.tags

  providers = {
    aws        = aws.hub
  }
}

module "gitops-bridge-bootstrap-eks" {
  source = "../argocd-bootstrap"
  
  create  = local.oss_addons.enable_argocd
  cluster = local.argocd_cluster_data
  apps    = local.argocd_apps
  argocd  = local.argocd_settings

  providers = {
    kubernetes = kubernetes.remote
    helm       = helm.remote
  }

  depends_on = [local.cluster_info]
}

module "gitops-bridge-bootstrap-kind" {
  source = "../argocd-bootstrap"

  create  = local.oss_addons.enable_argocd
  cluster = local.argocd_cluster_data
  apps    = local.argocd_apps
  argocd  = local.argocd_settings

  providers = {
    kubernetes = kubernetes.local
    helm       = helm.local
  }

  depends_on = [module.kind-hub]
}

module "eso_bootstrap-kind" {
  source = "../eso-bootstrap"

  namespace        = local.external_secrets.namespace
  argocd_namespace = local.argocd_namespace
  service_account  = local.external_secrets.service_account
  aws_region       = var.hub_aws_region
  cluster_name     = local.cluster_name
  repos            = local.gitops_private_repos

  providers = {
    helm       = helm.local
    kubernetes = kubernetes.local
  }

  depends_on = [module.kind-hub, module.gitops-bridge-bootstrap-kind]
}

module "eso_bootstrap-eks" {
  source = "../eso-bootstrap"

  namespace        = local.external_secrets.namespace
  argocd_namespace = local.argocd_namespace
  aws_region       = var.hub_aws_region
  cluster_name     = local.cluster_info.cluster_name
  service_account  = local.external_secrets.service_account
  repos            = local.gitops_private_repos

  providers = {
    helm       = helm.remote
    kubernetes = kubernetes.remote
  }

  depends_on = [module.eks-hub, module.gitops-bridge-bootstrap-eks]
}