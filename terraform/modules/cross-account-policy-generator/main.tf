###################################################################################################################################################
# Cross-Account Policy Generator Module
# Creates IAM policy documents for cross-account role assumption
###################################################################################################################################################

###################################################################################################################################################
# Cross-Account IAM Policy Document
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

  # Merge with any additional statements
  dynamic "statement" {
    for_each = var.additional_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}
