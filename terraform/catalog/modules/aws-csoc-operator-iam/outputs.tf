output "role_arns" {
  description = "Enabled operator role ARNs keyed by role function."
  value       = { for role_key, role in aws_iam_role.operator : role_key => role.arn }
}

output "role_names" {
  description = "Enabled operator role names keyed by role function."
  value       = { for role_key, role in aws_iam_role.operator : role_key => role.name }
}

output "user_role_arns" {
  description = "Operator role ARNs each configured IAM user is permitted to assume."
  value = {
    for user_key, role_keys in local.user_role_keys :
    user_key => [for role_key in role_keys : aws_iam_role.operator[role_key].arn]
  }
}

output "mfa_device_arns" {
  description = "Terraform-managed virtual MFA device ARNs keyed by user alias."
  value       = { for user_key, device in aws_iam_virtual_mfa_device.operator : user_key => device.arn }
}

output "mfa_enrollment" {
  description = "Sensitive enrollment data for newly created virtual MFA devices."
  sensitive   = true
  value = {
    for user_key, device in aws_iam_virtual_mfa_device.operator : user_key => {
      arn            = device.arn
      base32_seed    = device.base_32_string_seed
      qr_code_png    = device.qr_code_png
      enable_command = "aws iam enable-mfa-device --user-name ${var.users[user_key].name} --serial-number ${device.arn} --authentication-code-1 <CODE_1> --authentication-code-2 <CODE_2>"
    }
  }
}

output "default_role_key" {
  description = "Default role key for operator session tooling."
  value       = var.default_role_key
}

output "spoke_access_role_arns" {
  description = "Exact operator role ARNs approved for optional manual spoke access."
  value = [
    for role_key, role in local.active_roles :
    aws_iam_role.operator[role_key].arn if role.allow_spoke_access
  ]
}

output "eks_access_entries" {
  description = "Enabled operator roles that request an explicit EKS access policy."
  value = {
    for role_key, role in local.active_roles : role_key => {
      principal_arn     = aws_iam_role.operator[role_key].arn
      access_policy_arn = role.eks_access_policy_arn
    } if role.eks_access_policy_arn != ""
  }
}
