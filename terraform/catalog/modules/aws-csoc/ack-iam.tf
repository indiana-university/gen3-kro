###############################################################################
# ACK CSOC Source Role (shared across modes)
###############################################################################

resource "aws_iam_role" "ack_csoc_source" {
  count = local.ack_role_enabled ? 1 : 0
  name  = "${local.name}-csoc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "capabilities.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole"
        ]
      },
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.oidc_provider_id}:sub" = "system:serviceaccount:${local.ack_namespace}:ack-*-controller"
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    RoleType = "csoc-role"
  })
}

###############################################################################
# AWS-managed ACK capability (optional)
###############################################################################

resource "aws_eks_access_entry" "ack_csoc_source" {
  count         = local.ack_aws_managed && var.enable_ack_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.ack_csoc_source[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "ack_csoc_source_admin" {
  count         = local.ack_aws_managed && var.enable_ack_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.ack_csoc_source[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ack_csoc_source]
}

resource "aws_eks_capability" "ack" {
  count                     = local.ack_aws_managed && var.enable_ack_capability ? 1 : 0
  cluster_name              = module.eks.cluster_name
  type                      = "ACK"
  capability_name           = "ACK"
  role_arn                  = aws_iam_role.ack_csoc_source[0].arn
  delete_propagation_policy = "RETAIN"

  tags = merge(local.tags, {
    Name = "${local.name}-ack-capability"
    Type = "ACK"
  })

  depends_on = [
    aws_iam_role.ack_csoc_source,
    aws_eks_access_policy_association.ack_csoc_source_admin
  ]
}

###############################################################################
# Permission policy — allow CSOC source role to assume spoke roles
###############################################################################

resource "aws_iam_role_policy" "ack_csoc_assume_spoke" {
  count = local.ack_role_enabled ? 1 : 0
  name  = "${local.name}-csoc-assume-spoke"
  role  = aws_iam_role.ack_csoc_source[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeACKSpokeRoles"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Resource = "arn:aws:iam::*:role/*-spoke-role"
      }
    ]
  })
}
