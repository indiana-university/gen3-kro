###############################################################################
# Outputs
###############################################################################
output "inline_policy_document" {
  description = "Inline policy document JSON string with placeholders replaced"
  value       = local.policy_with_replacements
}

output "has_inline_policy" {
  description = "Whether an inline policy is provided"
  value       = local.has_inline_policy
}
