###############################################################################
# Outputs
###############################################################################
output "inline_policy_document" {
  description = "Inline policy document JSON string with placeholders replaced (AWS)"
  value       = local.policy_with_replacements
}

output "role_definition_json" {
  description = "Role definition JSON string with placeholders replaced (Azure)"
  value       = local.policy_with_replacements
}

output "role_definition_yaml" {
  description = "Role definition YAML string with placeholders replaced (GCP)"
  value       = local.policy_with_replacements
}

output "has_inline_policy" {
  description = "Whether an inline policy is provided"
  value       = local.has_inline_policy
}

output "has_role_definition" {
  description = "Whether a role definition is provided (Azure/GCP alias for has_inline_policy)"
  value       = local.has_inline_policy
}

output "policy_source" {
  description = "Source folder where the policy was loaded from"
  value       = var.policy_source
}
