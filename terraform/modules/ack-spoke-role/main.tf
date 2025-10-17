###################################################################################################################################################
# ACK Spoke Role Module
# Creates IAM role in spoke account that can be assumed by ACK pod identity from hub
###################################################################################################################################################

###################################################################################################################################################
# Spoke Account - IAM Role for Cross-Account Access
###################################################################################################################################################
resource "aws_iam_role" "spoke_ack" {
  count    = var.create ? 1 : 0

  name = "${var.spoke_alias}-ack-${var.service_name}-spoke-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = var.hub_pod_identity_role_arn
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  description = "Spoke role for ${var.cluster_name} ${var.service_name}-ack-controller in Spoke: ${var.spoke_alias}"
  tags        = var.tags
}

###################################################################################################################################################
# Attach Inline Policy to Spoke Role
###################################################################################################################################################
resource "aws_iam_role_policy" "spoke_ack_inline" {
  count    = var.create && var.has_inline_policy && var.combined_policy_json != null ? 1 : 0

  name   = "${var.service_name}-ack-policy"
  role   = aws_iam_role.spoke_ack[0].name
  policy = var.combined_policy_json
}

###################################################################################################################################################
# Attach Managed Policies to Spoke Role
###################################################################################################################################################
resource "aws_iam_role_policy_attachment" "spoke_ack_managed" {
  for_each = var.create && var.has_managed_policy ? var.policy_arns : {}
  provider = aws.spoke

  role       = aws_iam_role.spoke_ack[0].name
  policy_arn = each.value
}
