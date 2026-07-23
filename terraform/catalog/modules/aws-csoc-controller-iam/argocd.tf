###############################################################################
# Argo CD IAM
###############################################################################

resource "aws_iam_role" "argocd_self_managed" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed ? 1 : 0
  name  = "${local.name}-argocd-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
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

resource "aws_iam_role_policy" "argocd_inline" {
  count = local.argocd_self_managed && var.enable_argocd_self_managed && length(aws_iam_role.argocd_self_managed) > 0 ? 1 : 0
  name  = "${local.name}-argocd-controller-permissions"
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
