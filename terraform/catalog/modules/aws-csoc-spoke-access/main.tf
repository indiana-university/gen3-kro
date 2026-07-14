locals {
  spoke_role_arns = sort(distinct(compact(values(var.spoke_role_arns))))
  enabled         = var.source_role_name != "" && length(local.spoke_role_arns) > 0
}

resource "aws_iam_role_policy" "assume_spokes" {
  count = local.enabled ? 1 : 0

  name = var.policy_name
  role = var.source_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeACKSpokeRoles"
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = local.spoke_role_arns
    }]
  })
}
