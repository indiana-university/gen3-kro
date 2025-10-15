###################################################################################################################################################
# Hub Cluster Modules
###################################################################################################################################################
# Kind module removed - EKS-only infrastructure
# All environments now use EKS

###################################################################################################################################################
# GitOps Bridge and ArgoCD Bootstrap
###################################################################################################################################################
# Only install ArgoCD if cluster exists (checked via kube_providers.tf)
# This prevents Kubernetes provider errors during initial cluster creation
module "gitops-bridge-bootstrap" {
  source = "../../modules/argocd-bootstrap"

  create      = var.enable_argo && local.oss_addons.enable_argocd && try(local.cluster_exists, false)
  install     = var.enable_argo && try(local.cluster_exists, false)
  cluster     = local.argocd_cluster_data
  apps        = local.argocd_apps
  argocd      = local.argocd_settings
  outputs_dir = var.outputs_dir

  depends_on = [module.eks-hub]
}

###################################################################################################################################################
# IAM Access is now defined in iam-spoke.tf (inline in root module for dynamic provider support)
###################################################################################################################################################

###################################################################################################################################################
# End of File
###################################################################################################################################################
