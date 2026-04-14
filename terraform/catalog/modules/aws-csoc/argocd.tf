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
          "${local.oidc_provider_id}:sub" = [
            "system:serviceaccount:${var.argocd_namespace}:argocd-server",
            "system:serviceaccount:${var.argocd_namespace}:argocd-application-controller"
          ]
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

###############################################################################
# ArgoCD permission policies
###############################################################################

# Allow the ArgoCD role to assume spoke ArgoCD roles created by the RGD.
# Pattern mirrors ack_csoc_assume_spoke but scoped to *-argocd-spoke-role.
resource "aws_iam_role_policy" "argocd_assume_spoke" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed && length(aws_iam_role.argocd_self_managed) > 0 ? 1 : 0
  name  = "${local.name}-argocd-assume-spoke"
  role  = aws_iam_role.argocd_self_managed[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeArgoCDSpokeRoles"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Resource = "arn:aws:iam::*:role/*-argocd-spoke-role"
      }
    ]
  })
}

# Inline policy: Secrets Manager, SSM, and EKS read access for ArgoCD.
# Matches the reference policy at iam/_default/argocd/inline-policy.json.
resource "aws_iam_role_policy" "argocd_inline" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed && length(aws_iam_role.argocd_self_managed) > 0 ? 1 : 0
  name  = "${local.name}-argocd-inline"
  role  = aws_iam_role.argocd_self_managed[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArgoCDSecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "secretsmanager:Name" = ["argocd/*", "argo-cd/*"]
          }
        }
      },
      {
        Sid    = "ArgoCDParameterStoreAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ssm:Name" = ["/argocd/*", "/argo-cd/*"]
          }
        }
      },
      {
        Sid    = "EKSReadAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "kubernetes_namespace_v1" "argocd" {
  count = local.argocd_enabled ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "argocd"
    }
    annotations = {
      # Consumed by the KRO RGD (argocdNamespace externalRef) to build
      # the spoke ArgoCD role trust policy without hardcoding account IDs.
      "csoc-account-id" = local.csoc_account_id
    }
  }

  # Wait for ALL resources inside the EKS module to complete before the first Kubernetes API call
  depends_on = [module.eks]
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

resource "kubernetes_service_account_v1" "argocd_controller" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed && length(aws_iam_role.argocd_self_managed) > 0 ? 1 : 0

  metadata {
    name      = "argocd-application-controller"
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
    kubernetes_service_account_v1.argocd_controller,
    aws_iam_role.argocd_self_managed
  ]
}
