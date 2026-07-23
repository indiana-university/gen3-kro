data "aws_iam_user" "operator" {
  for_each  = var.users
  user_name = each.value.name
}

locals {
  active_roles = {
    for role_key, role in var.roles : role_key => role if role.enabled
  }

  active_role_principals = {
    for role_key, role in local.active_roles :
    role_key => distinct(concat(
      [for user_key in role.assigned_user_keys : data.aws_iam_user.operator[user_key].arn if contains(keys(var.users), user_key)],
      tolist(role.principal_arns)
    ))
  }

  user_role_keys = {
    for user_key, user in var.users :
    user_key => toset([
      for role_key, role in local.active_roles : role_key
      if contains(role.assigned_user_keys, user_key)
    ])
  }

  users_with_assume_policy = {
    for user_key, user in var.users : user_key => user
    if user.attach_assume_role_policy && length(local.user_role_keys[user_key]) > 0
  }

  users_with_managed_mfa = {
    for user_key, user in var.users : user_key => user if user.manage_virtual_mfa
  }
}

resource "aws_iam_virtual_mfa_device" "operator" {
  for_each = local.users_with_managed_mfa

  virtual_mfa_device_name = each.value.mfa_device_name
  tags = {
    for tag_key, tag_value in var.tags : tag_key => tag_value
    if !contains(["Module", "Stack"], tag_key)
  }

  lifecycle {
    precondition {
      condition     = trimspace(each.value.mfa_device_name) != ""
      error_message = "A user with manage_virtual_mfa=true must have a non-empty mfa_device_name."
    }
  }
}

resource "aws_iam_role" "operator" {
  for_each = local.active_roles

  name                 = each.value.name
  max_session_duration = each.value.max_session_duration
  tags = merge(var.tags, {
    Name     = each.value.name
    Module   = "aws-csoc-operator-iam"
    RoleKey  = each.key
    RoleType = "csoc-operator"
  })

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [merge({
      Sid    = each.value.require_mfa ? "AllowAssignedPrincipalsWithMFA" : "AllowAssignedPrincipals"
      Effect = "Allow"
      Principal = {
        AWS = local.active_role_principals[each.key]
      }
      Action = "sts:AssumeRole"
      }, each.value.require_mfa ? {
      Condition = {
        Bool = {
          "aws:MultiFactorAuthPresent" = "true"
        }
        NumericLessThan = {
          "aws:MultiFactorAuthAge" = tostring(each.value.max_session_duration)
        }
      }
    } : {})]
  })

  lifecycle {
    precondition {
      condition     = length(local.active_role_principals[each.key]) > 0
      error_message = "Every enabled operator role must have an assigned user or explicit principal ARN."
    }
  }
}

resource "aws_iam_role_policy" "operator_permissions" {
  for_each = local.active_roles

  name   = "${each.value.name}-permissions"
  role   = aws_iam_role.operator[each.key].id
  policy = each.value.permissions_policy
}

resource "aws_iam_user_policy" "assume_operator_roles" {
  for_each = local.users_with_assume_policy

  name = each.value.assume_role_policy_name != "" ? each.value.assume_role_policy_name : "allow-assume-csoc-operator-roles"
  user = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowAssignedCSOCOperatorRoles"
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = [for role_key in local.user_role_keys[each.key] : aws_iam_role.operator[role_key].arn]
    }]
  })
}
