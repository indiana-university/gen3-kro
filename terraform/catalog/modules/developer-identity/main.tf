###############################################################################
# Developer Identity Bootstrap — MFA + Scoped Assume-Role
#
# Creates:
#   1. Virtual MFA device for the IAM user (optional, var.create_virtual_mfa)
#   2. IAM role with scoped permissions (MFA-required trust policy)
#   3. IAM role policy — attaches permissions to the role
#   4. IAM user policy — allows the user to assume the role (optional)
#   5. Output files — MFA setup instructions + AWS config snippet
#
# Usage:
#   cd terraform/catalog/modules/developer-identity
#   terraform init
#   terraform apply
#   # Then follow the MFA registration instructions in the output
###############################################################################

###############################################################################
# Data Sources
###############################################################################

data "aws_caller_identity" "current" {}

# Guarded by count so an empty iam_user_name doesn't trigger a lookup error
data "aws_iam_user" "target" {
  count     = var.iam_user_name != "" ? 1 : 0
  user_name = var.iam_user_name
}

###############################################################################
# Locals
###############################################################################

locals {
  account_id            = data.aws_caller_identity.current.account_id
  effective_outputs_dir = var.outputs_dir != "" ? var.outputs_dir : "${path.module}/../../../../outputs"

  # Policy content: prefer file-based policy, fallback to inline_policy variable.
  # File must exist at iam/developer-identity/<policy_filename> relative to repo root.
  policy_content = (
    var.policy_filename != "" ?
    try(
      templatefile("${path.module}/../../../../iam/developer-identity/${var.policy_filename}", { account_id = local.account_id, region = var.region }),
      var.inline_policy
    ) :
    var.inline_policy
  )

  # Principal ARNs for the trust policy.
  # Priority: explicit assume_principal_arns > resolved IAM user ARN > account root.
  principal_arns = (
    length(var.assume_principal_arns) > 0
    ? var.assume_principal_arns
    : (
      var.iam_user_name != "" && length(data.aws_iam_user.target) > 0
      ? [data.aws_iam_user.target[0].arn]
      : ["arn:aws:iam::${local.account_id}:root"]
    )
  )

  # MFA seed display value — base_32_string_seed is null on imported devices;
  # try() only catches errors, not null values, so we use a ternary guard here.
  mfa_seed = (
    var.create_virtual_mfa && length(aws_iam_virtual_mfa_device.user_mfa) > 0
    ? (
      aws_iam_virtual_mfa_device.user_mfa[0].base_32_string_seed != null
      ? aws_iam_virtual_mfa_device.user_mfa[0].base_32_string_seed
      : "<run-apply-again-to-retrieve-seed>"
    )
    : ""
  )
}

###############################################################################
# 1. Virtual MFA Device
###############################################################################

resource "aws_iam_virtual_mfa_device" "user_mfa" {
  count                   = var.create_virtual_mfa ? 1 : 0
  virtual_mfa_device_name = var.mfa_device_name
  tags                    = var.tags
}

###############################################################################
# 2. IAM Role — Devcontainer assume-role
###############################################################################

resource "aws_iam_role" "devcontainer" {
  name                 = var.role_name
  max_session_duration = var.role_max_session_duration
  tags                 = var.tags

  # Trust policy is split into two variants to avoid serialising null into JSON,
  # which would produce an invalid AWS policy document.
  assume_role_policy = var.assume_requires_mfa ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPrincipalWithMFA"
        Effect = "Allow"
        Principal = {
          AWS = local.principal_arns
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
          NumericLessThan = {
            "aws:MultiFactorAuthAge" = tostring(var.role_max_session_duration)
          }
        }
      }
    ]
  }) : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPrincipal"
        Effect = "Allow"
        Principal = {
          AWS = local.principal_arns
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

###############################################################################
# 3. IAM Role Policy — Scoped permissions for the devcontainer role
###############################################################################

resource "aws_iam_role_policy" "devcontainer_permissions" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.devcontainer.id
  policy = local.policy_content
}

###############################################################################
# 4. IAM Policy on User — Allow AssumeRole to devcontainer role
###############################################################################

resource "aws_iam_user_policy" "allow_assume_devcontainer_role" {
  count = var.attach_user_policy && var.iam_user_name != "" && length(data.aws_iam_user.target) > 0 ? 1 : 0

  name = "allow-assume-${var.role_name}"
  user = var.iam_user_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAssumeDevcontainerRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.devcontainer.arn
      }
    ]
  })
}

###############################################################################
# 5. Output Files — MFA setup helper + AWS profile config snippet
###############################################################################

resource "local_file" "mfa_setup_instructions" {
  count           = var.create_virtual_mfa ? 1 : 0
  filename        = "${local.effective_outputs_dir}/mfa-setup-instructions.txt"
  file_permission = "0600"

  content = <<-EOT
    ═══════════════════════════════════════════════════════════════════
    MFA SETUP INSTRUCTIONS for ${var.iam_user_name}
    ═══════════════════════════════════════════════════════════════════

    1. The virtual MFA device has been created in AWS IAM.

    2. Register the MFA device with your authenticator app:

       Use the Base32 seed below to manually add the account to your
       authenticator app (Google Authenticator, Authy, 1Password, etc.):

      MFA ARN:     ${aws_iam_virtual_mfa_device.user_mfa[0].arn}
      Base32 Seed: ${local.mfa_seed}

       Or generate a QR code from this otpauth URI:
      otpauth://totp/AWS:${var.iam_user_name}@${local.account_id}?secret=${local.mfa_seed}&issuer=AWS

    3. After adding to your authenticator, enable the MFA device:

       aws iam enable-mfa-device \
         --user-name ${var.iam_user_name} \
         --serial-number ${aws_iam_virtual_mfa_device.user_mfa[0].arn} \
         --authentication-code-1 <CODE_1> \
         --authentication-code-2 <CODE_2> \
         --profile ${var.aws_profile}

       (Use two consecutive codes from your authenticator app)

    4. Add these profiles to your ~/.aws/config:

       [profile ${var.aws_profile}]
       region = ${var.region}
       output = yaml

       [profile eks-devcontainer]
       role_arn = ${aws_iam_role.devcontainer.arn}
       source_profile = ${var.aws_profile}
      mfa_serial = ${aws_iam_virtual_mfa_device.user_mfa[0].arn}
       region = ${var.region}
       output = yaml
       duration_seconds = ${var.role_max_session_duration}

    5. Test the setup:

       # This will prompt for your MFA code:
       aws sts get-caller-identity --profile eks-devcontainer

    ═══════════════════════════════════════════════════════════════════
    SECURITY NOTES
    ═══════════════════════════════════════════════════════════════════
    • Delete this file after completing setup — it contains the MFA seed
    • The devcontainer role has scoped permissions (not full admin)
    • Session tokens expire after ${var.role_max_session_duration / 3600} hours
    • Use scripts/mfa-session.sh to refresh sessions for the container
    • The devcontainer bind-mounts only ~/.aws/eks-devcontainer/ (not all of ~/.aws)
    ═══════════════════════════════════════════════════════════════════
  EOT
}

resource "local_file" "aws_config_snippet" {
  filename        = "${local.effective_outputs_dir}/aws-config-snippet.ini"
  file_permission = "0600"

  content = <<-EOT
    # Add these profiles to ~/.aws/config
    # The eks-devcontainer profile assumes the scoped role with MFA

    [profile eks-devcontainer]
    role_arn = ${aws_iam_role.devcontainer.arn}
    source_profile = ${var.aws_profile}
    mfa_serial = ${try(aws_iam_virtual_mfa_device.user_mfa[0].arn, "<register-mfa-separately>")}
    region = ${var.region}
    output = yaml
    duration_seconds = ${var.role_max_session_duration}
  EOT
}
