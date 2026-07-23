locals {
  namespace_enabled = var.enabled && (
    var.enable_argocd_self_managed ||
    var.enable_argocd_capability ||
    var.argocd_bootstrap_enabled
  )

  argocd_self_managed_enabled = var.enabled && var.enable_argocd_self_managed
  argocd_namespace_name       = local.namespace_enabled ? kubernetes_namespace_v1.argocd[0].metadata[0].name : var.argocd_namespace
}

resource "kubernetes_namespace_v1" "argocd" {
  count = local.namespace_enabled ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
    annotations = {
      "csoc-account-id" = var.csoc_account_id
    }
  }
}

resource "kubernetes_service_account_v1" "argocd" {
  count = local.argocd_self_managed_enabled ? 1 : 0

  metadata {
    name      = "argocd-server"
    namespace = local.argocd_namespace_name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.argocd_controller_role_arn
    }
  }
}

resource "kubernetes_service_account_v1" "argocd_controller" {
  count = local.argocd_self_managed_enabled ? 1 : 0

  metadata {
    name      = "argocd-application-controller"
    namespace = local.argocd_namespace_name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.argocd_controller_role_arn
    }
  }
}

resource "helm_release" "argocd" {
  count = local.argocd_self_managed_enabled ? 1 : 0

  name       = "argocd"
  repository = var.argocd_chart_repository
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = local.argocd_namespace_name

  set = [
    {
      name  = "server.serviceAccount.create"
      value = "false"
    },
    {
      name  = "server.serviceAccount.name"
      value = "argocd-server"
    },
    {
      name  = "controller.serviceAccount.create"
      value = "false"
    },
    {
      name  = "controller.serviceAccount.name"
      value = "argocd-application-controller"
    },
  ]

  values = length(var.argocd_values) > 0 ? [
    yamlencode(var.argocd_values)
  ] : []

  depends_on = [
    kubernetes_service_account_v1.argocd,
    kubernetes_service_account_v1.argocd_controller
  ]
}
