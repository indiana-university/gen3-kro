################################################################################
# ACK Spoke Roles Module - Main Configuration (V2)
# Single provider — spoke account only. No cross-account CSOC provider.
# Creates one IAM role per enabled role key.
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

  # IAM limits an inline role policy document to 10,240 bytes. Keep the
  # file-driven statement list split across a small number of managed policies.
  custom_policy_chunks = merge(
    {},
    [
      for role_key, config in local.active_roles : {
        for chunk_index, statements in chunklist(lookup(config, "custom_policies", []), 8) :
        "${role_key}-${chunk_index}" => {
          role_key    = role_key
          chunk_index = chunk_index
          statements  = statements
        }
      }
      if length(lookup(config, "custom_policies", [])) > 0
    ]...
  )

  custom_policy_inline_chunks = {
    for key, chunk in local.custom_policy_chunks :
    key => chunk if chunk.chunk_index == 0
  }

  custom_policy_managed_chunks = {
    for key, chunk in local.custom_policy_chunks :
    key => chunk if chunk.chunk_index > 0
  }

  assume_role_policies = {
    for role_key in keys(local.active_roles) : role_key => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid    = "ExactCSOCSourceRole"
          Effect = "Allow"
          Principal = {
            AWS = [var.csoc_source_role_arn]
          }
          Action = "sts:AssumeRole"
        }],
        length(var.manual_operator_role_arns) > 0 ? [{
          Sid    = "ExactOperatorManualAccess"
          Effect = "Allow"
          Principal = {
            AWS = sort(tolist(var.manual_operator_role_arns))
          }
          Action = "sts:AssumeRole"
        }] : []
      )
    })
  }
}

################################################################################
# Trust Policy
#
# The controller state supplies the exact CSOC ACK controller role ARN.
################################################################################

resource "aws_iam_role" "ack_workload" {
  for_each = local.active_roles

  name        = "${var.spoke_alias}-${each.key}-access-role"
  description = "ACK spoke role for ${var.spoke_alias} managed by ${var.cluster_name}"

  assume_role_policy = local.assume_role_policies[each.key]

  tags = merge(
    var.tags,
    {
      Name       = "${var.spoke_alias}-${each.key}-access-role"
      SpokeAlias = var.spoke_alias
      Cluster    = var.cluster_name
      ManagedBy  = "terraform"
      Module     = "aws-spoke-access-iam"
      RoleKey    = each.key
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
  for_each = local.custom_policy_inline_chunks

  name = "${var.spoke_alias}-${each.value.role_key}-access-inline-00"
  role = aws_iam_role.ack_workload[each.value.role_key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.statements :
      try(jsondecode(stmt), stmt)
    ]
  })
}

resource "aws_iam_policy" "custom_managed_policies" {
  for_each = local.custom_policy_managed_chunks

  name        = format("%s-%s-access-managed-%02d", var.spoke_alias, each.value.role_key, each.value.chunk_index)
  description = format("ACK spoke role custom policy chunk %02d for %s", each.value.chunk_index, var.spoke_alias)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for stmt in each.value.statements :
      try(jsondecode(stmt), stmt)
    ]
  })
}

resource "aws_iam_role_policy_attachment" "custom_managed_policy_attachments" {
  for_each = local.custom_policy_managed_chunks

  role       = aws_iam_role.ack_workload[each.value.role_key].name
  policy_arn = aws_iam_policy.custom_managed_policies[each.key].arn
}
