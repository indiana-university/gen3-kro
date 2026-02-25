###############################################################################
# AWS-managed KRO and ArgoCD capabilities (optional)
###############################################################################

resource "aws_iam_role" "kro_controller" {
  count = local.kro_aws_managed && var.enable_kro_capability ? 1 : 0
  name  = "${local.name}-kro-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.tags
}

resource "aws_eks_access_entry" "kro_controller" {
  count         = local.kro_aws_managed && var.enable_kro_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.kro_controller[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "kro_controller_admin" {
  count         = local.kro_aws_managed && var.enable_kro_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.kro_controller[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.kro_controller]
}

resource "aws_eks_capability" "kro" {
  count                     = local.kro_aws_managed && var.enable_kro_capability ? 1 : 0
  cluster_name              = module.eks.cluster_name
  type                      = "KRO"
  capability_name           = "KRO"
  role_arn                  = aws_iam_role.kro_controller[0].arn
  delete_propagation_policy = "RETAIN"

  tags = merge(local.tags, {
    Name = "${local.name}-kro-capability"
    Type = "KRO"
  })

  depends_on = [
    aws_iam_role.kro_controller,
    aws_eks_access_policy_association.kro_controller_admin
  ]
}

resource "aws_iam_role" "argocd_controller" {
  count = local.argocd_aws_managed && var.enable_argocd_capability ? 1 : 0
  name  = "${local.name}-argocd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.tags
}

resource "aws_eks_access_entry" "argocd_controller" {
  count         = local.argocd_aws_managed && var.enable_argocd_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_controller[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "argocd_controller_admin" {
  count         = local.argocd_aws_managed && var.enable_argocd_capability ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_controller[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.argocd_controller]
}

resource "aws_eks_capability" "argocd" {
  count                     = local.argocd_aws_managed && var.enable_argocd_capability ? 1 : 0
  cluster_name              = module.eks.cluster_name
  type                      = "ARGOCD"
  capability_name           = "ARGOCD"
  role_arn                  = aws_iam_role.argocd_controller[0].arn
  delete_propagation_policy = "RETAIN"

  tags = merge(local.tags, {
    Name = "${local.name}-argocd-capability"
    Type = "ARGOCD"
  })

  depends_on = [
    aws_iam_role.argocd_controller,
    aws_eks_access_policy_association.argocd_controller_admin,
    kubernetes_namespace_v1.argocd
  ]
}
