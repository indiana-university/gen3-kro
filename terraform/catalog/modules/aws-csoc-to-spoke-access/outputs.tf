output "spoke_role_arns" {
  description = "Exact spoke role ARNs included in the policy"
  value       = local.spoke_role_arns
}

output "policy_name" {
  description = "Name of the managed inline policy"
  value       = try(aws_iam_role_policy.assume_spokes[0].name, null)
}
