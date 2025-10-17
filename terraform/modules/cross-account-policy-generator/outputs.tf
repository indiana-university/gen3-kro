output "policy_json" {
  description = "The cross-account policy document as JSON"
  value       = try(data.aws_iam_policy_document.cross_account[0].json, null)
}

output "policy_statements" {
  description = "The policy statements in the cross-account policy"
  value       = try(data.aws_iam_policy_document.cross_account[0].statement, [])
}
