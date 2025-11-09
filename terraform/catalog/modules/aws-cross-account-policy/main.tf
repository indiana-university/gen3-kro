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
  count = var.create ? 1 : 0

  statement {
    sid    = "AssumeRoleInSpokeAccount"
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    resources = length(var.spoke_role_arns) > 0 ? var.spoke_role_arns : ["arn:aws:iam::*:role/placeholder-no-spokes"]
  }
}

###################################################################################################################################################
# IAM Role Policy - Attach to CSOC Pod Identity Role
# Note: We create this unconditionally when var.create=true. If spoke_role_arns ends up empty,
# the policy will allow assuming a placeholder role that doesn't exist, which is harmless.
# In practice, the generate block should only create these modules when spokes exist.
###################################################################################################################################################
resource "aws_iam_role_policy" "cross_account" {
  count = var.create ? 1 : 0

  name   = "${var.service_name}-cross-account-assume"
  role   = local.csoc_role_name
  policy = data.aws_iam_policy_document.cross_account[0].json
}
