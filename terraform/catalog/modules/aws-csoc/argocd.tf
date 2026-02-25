###############################################################################
# ArgoCD Self-Managed (Helm)
###############################################################################

resource "aws_iam_role" "argocd_self_managed" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed ? 1 : 0
  name  = "${local.name}-argocd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:${var.argocd_namespace}:argocd-server"
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

resource "kubernetes_namespace_v1" "argocd" {
  count = local.argocd_enabled ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
  }
}

resource "kubernetes_service_account_v1" "argocd" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed && length(aws_iam_role.argocd_self_managed) > 0 ? 1 : 0

  metadata {
    name      = "argocd-server"
    namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_self_managed[0].arn
    }
  }
}

resource "helm_release" "argocd" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed ? 1 : 0

  name       = "argocd"
  repository = var.argocd_chart_repository
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd[0].metadata[0].name

  set = [
    {
      name  = "server.serviceAccount.create"
      value = "false"
    },
    {
      name  = "server.serviceAccount.name"
      value = "argocd-server"
    },
  ]

  values = length(var.argocd_values) > 0 ? [
    yamlencode(var.argocd_values)
  ] : []

  depends_on = [
    kubernetes_service_account_v1.argocd,
    aws_iam_role.argocd_self_managed
  ]
}
