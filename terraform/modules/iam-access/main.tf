#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Data Sources
#-------------------------------------------------------------------------------------------------------------------------------------------------#
data "aws_caller_identity" "spoke" {
  provider = aws.spoke
}

# Fetch the recommended policy ARNs
data "http" "policy_arn" {
  for_each = local.policy_arn_urls
  url      = each.value
}

# Fetch the recommended inline policies
data "http" "inline_policy" {
  for_each = local.inline_policy_urls
  url      = each.value
}

locals {
  spoke_account_id      = data.aws_caller_identity.spoke.account_id 
  enable_external_spoke = var.hub_account_id != local.spoke_account_id && var.environment == "prod" ? true : false
  enable_internal_spoke = var.hub_account_id == local.spoke_account_id && var.environment == "prod" ? true : false
  policy_arn_urls       = { for service in var.ack_services : service => "https://raw.githubusercontent.com/aws-controllers-k8s/${service}-controller/main/config/iam/recommended-policy-arn"}
  inline_policy_urls    = { for service in var.ack_services : service => "https://raw.githubusercontent.com/aws-controllers-k8s/${service}-controller/main/config/iam/recommended-inline-policy"}
  valid_policies        = {
    for k, v in data.http.policy_arn : k => v.status_code == 200 ? trimspace(v.body) : null
  }
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# External Account Spoke Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers in the hub account
resource "aws_iam_role" "ack_hub" {
  provider = aws.hub
  for_each = local.enable_external_spoke ? toset(var.ack_services) : [] # Only create if external spoke is enabled
  name        = "${local.spoke_account_id}-ack-${each.key}-hub-role"

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

# Then create spoke cross-account access policy in the hub account
data "aws_iam_policy_document" "ack_hub_cross_account_policy" {
  provider = aws.hub
  for_each = local.enable_external_spoke ? toset(var.ack_services) : []

  statement {
    sid    = "AllowCrossAccountAccess"
    effect = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:aws:iam::${local.spoke_account_id}:role/eks-cluster-mgmt-${each.key}"]
  }
}
# Then attach the policy to the role in the hub account
resource "aws_iam_role_policy" "ack_hub_cross_account_policy" {
  provider = aws.hub
  for_each = local.enable_external_spoke ? toset(var.ack_services) : []

  role   = aws_iam_role.ack_hub[each.key].name
  policy = data.aws_iam_policy_document.ack_hub_cross_account_policy[each.key].json
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers in the spoke account
resource "aws_iam_role" "ack_spoke" {
  provider = aws.spoke
  for_each = local.enable_external_spoke ? toset(var.ack_services) : []

  name = "ack-${each.key}-spoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.hub_account_id}:root"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  description = "Spoke role for ACK ${each.key} controller assumed by hub account"
  tags        = var.tags
}

# Then create IAM policies for ACK controllers if there is a valid inline policy
resource "aws_iam_role_policy_attachment" "spoke_service_policies" {
  provider   = aws.spoke
  for_each = local.enable_external_spoke ? {
    for k, v in local.valid_policies : k => v
    if v != null && can(regex("^arn:aws", v))
  } : {}
  role       = aws_iam_role.ack_spoke[each.key].name
  policy_arn = each.value
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Same Account Spoke Access
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Create IAM roles for ACK controllers with the hub account
resource "aws_iam_role" "ack_controller" {
  provider = aws.hub
  for_each = local.enable_internal_spoke ? toset(var.ack_services) : []

  name        = "ack-${each.key}-controller-role"
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

# Then create inline policies for ACK controllers if there is a valid inline policy
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_role_policy" "ack_controller_inline_policy" {
  provider = aws.hub
  for_each = local.enable_internal_spoke ? toset(var.ack_services) : []

  role   = aws_iam_role.ack_controller[each.key].name
  policy = can(jsondecode(data.http.inline_policy[each.key].body)) ? trimspace(data.http.inline_policy[each.key].body) : jsonencode({

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

# Then attach policy only when there's a valid policy ARN
resource "aws_iam_role_policy_attachment" "ack_controller_policy_attachment" {
  provider   = aws.hub
  for_each = local.enable_internal_spoke ? {
    for k, v in local.valid_policies : k => v
    if v != null && can(regex("^arn:aws", v))
  } : {}

  role       = aws_iam_role.ack_controller[each.key].name
  policy_arn = each.value
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# ACK Controllers' Pod Identity Association
#-------------------------------------------------------------------------------------------------------------------------------------------------#
resource "aws_eks_pod_identity_association" "ack_controller" {
  provider = aws.hub
  for_each = local.enable_internal_spoke ? {for svc in var.ack_services : svc => var.ack_services_config[svc] } : {}

  cluster_name    = var.cluster_info.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.ack_controller[each.key].arn
}

resource "aws_eks_pod_identity_association" "ack_spoke" {
  provider = aws.spoke
  for_each = local.enable_external_spoke ? {for svc in var.ack_services : svc => var.ack_services_config[svc] } : {}

  cluster_name    = var.cluster_info.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.ack_spoke[each.key].arn
}
