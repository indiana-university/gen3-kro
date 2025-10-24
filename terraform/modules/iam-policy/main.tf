###################################################################################################################################################
# Generic IAM Policy Module - Main Logic
###################################################################################################################################################

locals {
  # Build filesystem paths for policy files
  # Pattern: {base_path}/{provider}/{context}/{service_name}/
  context_base_path  = "${var.iam_policy_base_path}/${var.provider}/${var.context}/${var.service_name}"
  default_base_path  = "${var.iam_policy_base_path}/${var.provider}/_default/${var.service_name}"

  # Local filesystem absolute paths
  local_context_path = var.repo_root_path != "" ? "${var.repo_root_path}/${local.context_base_path}" : "${path.root}/${local.context_base_path}"
  local_default_path = var.repo_root_path != "" ? "${var.repo_root_path}/${local.default_base_path}" : "${path.root}/${local.default_base_path}"

  # Policy file names vary by provider
  policy_file_name = var.provider == "aws" ? "inline-policy.json" : (
    var.provider == "azure" ? "role-definition.json" : "role.yaml"
  )
}

###################################################################################################################################################
# HTTP Data Sources - Fetch policies from GitHub raw content URLs (primary source)
###################################################################################################################################################
// HTTP fetching disabled: IAM policies are loaded from local filesystem only

locals {
  # Filesystem loading with _default fallback
  fs_inline_policy_context = try(file("${local.local_context_path}/${local.policy_file_name}"), null)
  fs_inline_policy_default = try(file("${local.local_default_path}/${local.policy_file_name}"), null)

  fs_managed_arns_context = try(jsondecode(file("${local.local_context_path}/source-policy-arn.json")), {})
  fs_managed_arns_default = try(jsondecode(file("${local.local_default_path}/source-policy-arn.json")), {})

  fs_override_policy_context = try(file("${local.local_context_path}/overridepolicy.json"), null)
  fs_override_policy_default = try(file("${local.local_default_path}/overridepolicy.json"), null)

  # Pick context first, then _default
  fs_inline_policy   = local.fs_inline_policy_context != null ? local.fs_inline_policy_context : local.fs_inline_policy_default
  fs_managed_arns    = length(local.fs_managed_arns_context) > 0 ? local.fs_managed_arns_context : local.fs_managed_arns_default
  fs_override_policy = local.fs_override_policy_context != null ? local.fs_override_policy_context : local.fs_override_policy_default

  # Final policies (custom > filesystem)
  final_inline_policy   = var.custom_inline_policy != null ? var.custom_inline_policy : local.fs_inline_policy
  final_policy_arns     = length(var.custom_managed_arns) > 0 ? var.custom_managed_arns : local.fs_managed_arns
  final_override_policy = var.custom_override_policy != null ? var.custom_override_policy : local.fs_override_policy

  # Build output lists
  override_policy_documents = local.final_override_policy != null ? [local.final_override_policy] : []

  # Track actual source used (custom, filesystem, or none)
  actual_source = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0 ? "custom" : (
    local.fs_inline_policy != null || length(local.fs_managed_arns) > 0 ? "filesystem" : "none"
  )
}

###################################################################################################################################################
# Outputs
###################################################################################################################################################
output "inline_policy_document" {
  description = "Inline policy document (if any)"
  value       = local.final_inline_policy
}

output "managed_policy_arns" {
  description = "Map of managed policy ARNs"
  value       = local.final_policy_arns
}

output "override_policy_documents" {
  description = "List of override policy documents"
  value       = local.override_policy_documents
}

output "has_inline_policy" {
  description = "Whether an inline policy was found or provided"
  value       = local.final_inline_policy != null
}

output "has_managed_policies" {
  description = "Whether managed policies were found or provided"
  value       = length(local.final_policy_arns) > 0
}

output "policy_source" {
  description = "Actual source of the policy: filesystem, custom, or none"
  value       = local.actual_source
}

output "debug_paths" {
  description = "Debug: paths being checked for policy files"
  value = {
    provider            = var.provider
    context_path        = local.local_context_path
    default_path        = local.local_default_path
    policy_file_name    = local.policy_file_name
    repo_root_path      = var.repo_root_path
    service_name        = var.service_name
    fs_inline_found     = local.fs_inline_policy != null
    final_inline_found  = local.final_inline_policy != null
    policy_source       = local.actual_source
  }
}
