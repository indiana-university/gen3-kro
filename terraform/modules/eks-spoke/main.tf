data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# Fetch the recommended policy ARNs
data "http" "policy_arn" {
  for_each = var.policy_arn_urls
  url      = each.value
}

# Fetch the recommended inline policies
data "http" "inline_policy" {
  for_each = var.inline_policy_urls
  url      = each.value
}

data "aws_iam_policy_document" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  statement {
    sid    = "AllowCrossAccountAccess"
    effect = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = [
      for account in split(" ", var.account_ids) : "arn:aws:iam:::role/eks-cluster-mgmt-${each.key}"
    ]
  }
}


#-------------------------------------------------------------------------------------------------------------------------------------------------#
# IAM Roles and Policies for kro controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers
resource "aws_iam_role" "ack_controller" {
  for_each = toset(["iam", "ec2", "eks"])
  name        = "ack-${each.key}-controller-role-mgmt"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "AllowEksAuthToAssumeRoleForPodIdentity"
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
      }
    ]
  })
  description = "IRSA role for ACK ${each.key} controller deployment on EKS cluster using Helm charts"
  tags        = var.tags
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Then create IAM policies for ACK controllers if the policy is valid
resource "aws_iam_role_policy" "ack_controller_inline_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = can(jsondecode(data.http.inline_policy[each.key].body)) ? data.http.inline_policy[each.key].body : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "${each.key}:*"
        ]
        Resource = "*"
      }
    ]
  })
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Then attachment policy only when there's a valid policy ARN
resource "aws_iam_role_policy_attachment" "ack_controller_policy_attachment" {
  for_each = {
    for k, v in var.valid_policies : k => v
    if v != null && can(regex("^arn:aws", v))
  }

  role       = aws_iam_role.ack_controller[each.key].name
  policy_arn = each.value
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Cross-account access policy for ACK controllers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  role   = aws_iam_role.ack_controller[each.key].name
  policy = data.aws_iam_policy_document.ack_controller_cross_account_policy[each.key].json
}

