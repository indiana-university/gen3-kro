data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_ecr_authorization_token" "token" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_ssm_parameter" "private_keys" {
  for_each        = toset(var.private_key_paths)
  name            = each.value
  with_decryption = true
}

# Fetch the recommended policy ARNs
data "http" "policy_arn" {
  for_each = var.policy_arn_urls
  url      = each.value
}

# Fetch the recommended inline policies
data "http" "inline_policy" {
  for_each = var.inline_policy_urls
  url      = each.value
}

data "aws_iam_policy_document" "ack_controller_cross_account_policy" {
  for_each = toset(["iam", "ec2", "eks"])

  statement {
    sid    = "AllowCrossAccountAccess"
    effect = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    resources = [
      for account in split(" ", var.account_ids) : "arn:aws:iam:::role/eks-cluster-mgmt-${each.key}"
    ]
  }
}

