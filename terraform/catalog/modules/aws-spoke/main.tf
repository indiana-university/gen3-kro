################################################################################
# ACK Workload Roles Module - Main Configuration (V2)
# Single provider — spoke account only. No cross-account CSOC provider.
################################################################################

data "aws_caller_identity" "spoke" {}

locals {
  role_name_prefix = "ack-workload"
  spoke_account_id = data.aws_caller_identity.spoke.account_id
  role_inputs = {
    for name, cfg in var.roles :
    name => merge(
      {
        enabled          = true
        managed_policies = []
        custom_policies  = []
      },
      cfg
    )
  }

  # Filter to only enabled roles
  active_roles = {
    for k, v in local.role_inputs : k => v if v.enabled
  }
}

################################################################################
# Trust Policy — Account-Root + ArnLike Condition (V2)
################################################################################

data "aws_iam_policy_document" "assume_role" {
  for_each = local.active_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.csoc_account_id}:root"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.csoc_account_id}:role/*ack-shared-*-source"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.cluster_name]
    }
  }
}

################################################################################
# IAM Roles for ACK Workload Operations
################################################################################

resource "aws_iam_role" "ack_workload" {
  for_each = local.active_roles

  name        = "${local.role_name_prefix}-${each.key}"
  description = "ACK workload role for ${each.key} in ${var.cluster_name}"

  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(
    var.tags,
    {
      Name      = "${local.role_name_prefix}-${each.key}"
      RoleKey   = each.key
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
      Module    = "ack-workload-roles"
    }
  )
}

################################################################################
# Attach AWS Managed Policies
################################################################################

resource "aws_iam_role_policy_attachment" "managed_policies" {
  for_each = {
    for pair in flatten([
      for role_key, config in local.active_roles : [
        for policy in config.managed_policies : {
          key        = "${role_key}-${replace(policy, "/[/:]/", "-")}"
          role       = role_key
          policy_arn = policy
        }
      ]
    ]) : pair.key => pair
  }

  role       = aws_iam_role.ack_workload[each.value.role].name
  policy_arn = each.value.policy_arn
}

################################################################################
# Custom Inline Policies (if needed)
################################################################################

resource "aws_iam_role_policy" "custom_policies" {
  for_each = {
    for role_key, config in local.active_roles :
    role_key => config
    if length(lookup(config, "custom_policies", [])) > 0
  }

  name = "${local.role_name_prefix}-${each.key}-custom"
  role = aws_iam_role.ack_workload[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.custom_policies :
      try(jsondecode(stmt), stmt)
    ]
  })
}

