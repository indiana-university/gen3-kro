###############################################################################
# Outputs
###############################################################################
output "inline_policy_document" {
  description = "Inline policy document JSON string"
  value       = var.policy_inline_json
}

output "has_inline_policy" {
  description = "Whether an inline policy is provided"
  value       = local.has_inline_policy
}

