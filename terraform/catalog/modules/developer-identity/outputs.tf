###############################################################################
# Outputs — Developer Identity Bootstrap
###############################################################################

output "mfa_device_arn" {
  description = "ARN of the virtual MFA device (empty string if create_virtual_mfa=false)"
  value       = try(aws_iam_virtual_mfa_device.user_mfa[0].arn, "")
}

output "mfa_base32_seed" {
  description = "Base32 seed for MFA authenticator app registration (empty string if create_virtual_mfa=false)"
  value       = try(aws_iam_virtual_mfa_device.user_mfa[0].base_32_string_seed, "")
  sensitive   = true
}

output "mfa_qr_code_uri" {
  description = "otpauth:// URI for QR code generation (empty string if create_virtual_mfa=false)"
  value       = try("otpauth://totp/AWS:${var.iam_user_name}@${local.account_id}?secret=${aws_iam_virtual_mfa_device.user_mfa[0].base_32_string_seed}&issuer=AWS", "")
  sensitive   = true
}

output "devcontainer_role_arn" {
  description = "ARN of the devcontainer IAM role"
  value       = aws_iam_role.devcontainer.arn
}

output "devcontainer_role_name" {
  description = "Name of the devcontainer IAM role"
  value       = aws_iam_role.devcontainer.name
}

output "enable_mfa_command" {
  description = "AWS CLI command to enable the MFA device (replace CODE_1 and CODE_2; empty if create_virtual_mfa=false)"
  value       = try("aws iam enable-mfa-device --user-name ${var.iam_user_name} --serial-number ${aws_iam_virtual_mfa_device.user_mfa[0].arn} --authentication-code-1 <CODE_1> --authentication-code-2 <CODE_2> --profile ${var.aws_profile}", "")
}

output "aws_config_profile" {
  description = "AWS CLI profile block to add to ~/.aws/config"
  value       = <<-EOT
    [profile ${var.role_name}]
    role_arn = ${aws_iam_role.devcontainer.arn}
    source_profile = ${var.aws_profile}
    mfa_serial = ${try(aws_iam_virtual_mfa_device.user_mfa[0].arn, "<register-mfa-separately>")}
    region = ${var.region}
    output = yaml
    duration_seconds = ${var.role_max_session_duration}
  EOT
}

output "mfa_session_script_usage" {
  description = "How to use the MFA session helper script"
  value       = "bash scripts/mfa-session.sh <MFA_CODE>"
}
