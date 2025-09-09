###################################################################################################################################################
# GitOps Bridge: Bootstrap
###################################################################################################################################################
module "gitops_bridge_bootstrap" {
  source  = "../gitops-bridge"
  cluster = {
    cluster_name = var.cluster_info.cluster_name
    environment  = var.environment
    metadata     = var.addons_metadata
    addons       = var.local_addons
  }

  apps = var.argocd_apps
  argocd = {
    name             = "argocd"
    namespace        = var.argocd_namespace
    chart_version    = var.argocd_chart_version
    values           = [file("${path.module}/argocd-initial-values.yaml")]
    timeout          = 600
    create_namespace = false
  }
    depends_on = [kubernetes_namespace.argocd]
}
###################################################################################################################################################
# ArgoCD Namespace and SSH Secret
###################################################################################################################################################
resource "kubernetes_namespace" "argocd" {
  depends_on = [var.cluster_info]

  metadata {
    name = var.argocd_namespace
  }
}

