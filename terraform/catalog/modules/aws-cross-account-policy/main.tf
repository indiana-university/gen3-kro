###################################################################################################################################################
# Cross-Account Policy Module
# Creates IAM policy to allow CSOC pod identity to assume roles in all spoke accounts
###################################################################################################################################################

###################################################################################################################################################
# Locals - Extract role name from ARN
###################################################################################################################################################
locals {
  # Extract role name from ARN (format: arn:aws:iam::account-id:role/role-name)
  csoc_role_name = var.create ? element(split("/", var.csoc_pod_identity_role_arn), length(split("/", var.csoc_pod_identity_role_arn)) - 1) : ""
}

###################################################################################################################################################
# IAM Policy Document - Cross-Account AssumeRole
###################################################################################################################################################
data "aws_iam_policy_document" "cross_account" {
  count = var.create && length(var.spoke_role_arns) > 0 ? 1 : 0

  statement {
    sid    = "AssumeRoleInSpokeAccount"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    resources = var.spoke_role_arns
  }
}

###################################################################################################################################################
# IAM Role Policy - Attach to CSOC Pod Identity Role
###################################################################################################################################################
resource "aws_iam_role_policy" "cross_account" {
  count = var.create && length(var.spoke_role_arns) > 0 ? 1 : 0

  name   = "${var.service_name}-cross-account-assume"
  role   = local.csoc_role_name
  policy = data.aws_iam_policy_document.cross_account[0].json
}
