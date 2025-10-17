output "source_policy_documents" {
  description = "List of source policy documents (from ACK repo)"
  value       = local.source_policy_documents
}

output "override_policy_documents" {
  description = "List of override policy documents (from local files or URLs)"
  value       = local.override_policy_documents
}

output "policy_arns" {
  description = "Map of managed policy ARNs to attach"
  value       = local.all_policy_arns
}

output "combined_policy_json" {
  description = "Combined policy document JSON (if inline policies exist)"
  value       = var.create && length(data.aws_iam_policy_document.ack_policy) > 0 ? data.aws_iam_policy_document.ack_policy[0].json : null
}

output "has_inline_policy" {
  description = "Whether inline policies are available"
  value       = length(local.source_policy_documents) > 0 || length(local.override_policy_documents) > 0
}

output "has_managed_policy" {
  description = "Whether managed policy ARNs are available"
  value       = length(local.all_policy_arns) > 0
}

output "service_name" {
  description = "ACK service name"
  value       = var.service_name
}
