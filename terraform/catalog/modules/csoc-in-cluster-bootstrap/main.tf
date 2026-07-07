locals {
  namespace_enabled = var.enabled && (
    var.enable_argocd_self_managed ||
    var.enable_argocd_capability ||
    var.argocd_bootstrap_enabled
  )

  argocd_self_managed_enabled = var.enabled && var.enable_argocd_self_managed
  bootstrap_enabled           = var.enabled && var.argocd_bootstrap_enabled

  argocd_namespace_name = local.namespace_enabled ? kubernetes_namespace_v1.argocd[0].metadata[0].name : var.argocd_namespace
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
      "eks.amazonaws.com/role-arn" = var.argocd_self_managed_role_arn
    }
  }
}

resource "kubernetes_service_account_v1" "argocd_controller" {
  count = local.argocd_self_managed_enabled ? 1 : 0

  metadata {
    name      = "argocd-application-controller"
    namespace = local.argocd_namespace_name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.argocd_self_managed_role_arn
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

module "argocd_bootstrap" {
  source = "../argocd-bootstrap"

  enabled = local.bootstrap_enabled

  aws_profile                        = var.aws_profile
  region                             = var.region
  cluster_name                       = var.cluster_name
  cluster_endpoint                   = var.cluster_endpoint
  cluster_certificate_authority_data = var.cluster_certificate_authority_data

  argocd_namespace           = local.argocd_namespace_name
  ssm_repo_secret_names      = var.ssm_repo_secret_names
  argocd_cluster_secret_name = var.argocd_cluster_secret_name
  argocd_cluster_labels      = var.argocd_cluster_labels
  argocd_cluster_annotations = var.argocd_cluster_annotations
  ack_self_managed_role_arn  = var.ack_self_managed_role_arn
  spoke_account_ids          = var.spoke_account_ids
  outputs_dir                = var.outputs_dir
  stack_dir                  = var.stack_dir
  bootstrap_dependency_token = join(",", concat(
    compact([var.foundation_dependency_token]),
    kubernetes_namespace_v1.argocd[*].metadata[0].name,
    helm_release.argocd[*].name
  ))
}
