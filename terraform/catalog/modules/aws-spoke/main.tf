################################################################################
# ACK Spoke Roles Module - Main Configuration (V2)
# Single provider — spoke account only. No cross-account CSOC provider.
# Creates one IAM role per spoke: ${spoke_alias}-spoke-role
################################################################################

data "aws_caller_identity" "spoke" {}

locals {
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
# ArnLike restricts callers to the CSOC source role (*-csoc-role).
# No ExternalId — ACK does not pass it during sts:AssumeRole.
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
      values   = ["arn:aws:iam::${var.csoc_account_id}:role/*-csoc-role"]
    }
  }
}

################################################################################
# IAM Roles for ACK Spoke Operations
# Role name: ${spoke_alias}-spoke-role (one per spoke)
################################################################################

resource "aws_iam_role" "ack_workload" {
  for_each = local.active_roles

  name        = "${var.spoke_alias}-spoke-role"
  description = "ACK spoke role for ${var.spoke_alias} managed by ${var.cluster_name}"

  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(
    var.tags,
    {
      Name      = "${var.spoke_alias}-spoke-role"
      SpokeAlias = var.spoke_alias
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
      Module    = "aws-spoke"
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

  name = "${var.spoke_alias}-spoke-role-custom"
  role = aws_iam_role.ack_workload[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.custom_policies :
      try(jsondecode(stmt), stmt)
    ]
  })
}

resource "aws_iam_role_policy" "custom_policies_2" {
  for_each = {
    for role_key, config in local.active_roles :
    role_key => config
    if length(lookup(config, "custom_policies_2", [])) > 0
  }

  name = "${var.spoke_alias}-spoke-role-custom-2"
  role = aws_iam_role.ack_workload[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.custom_policies_2 :
      try(jsondecode(stmt), stmt)
    ]
  })
}

