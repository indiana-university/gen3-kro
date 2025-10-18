###################################################################################################################################################
# Generic IAM Policy Module - Main Logic
###################################################################################################################################################

locals {
  # Determine if we're using Git URLs or local paths
  use_git_urls = var.iam_policy_repo_url != ""

  # Build paths for policy files
  # Pattern: {base_path}/gen3-kro/{context}/{service_type}/{service_name}/
  context_base_path = "${var.iam_policy_base_path}/gen3-kro/${var.context}/${var.service_type}/${var.service_name}"
  hub_base_path     = "${var.iam_policy_base_path}/gen3-kro/hub/${var.service_type}/${var.service_name}"

  # Full paths (Git or local)
  context_path = local.use_git_urls ? "${var.iam_policy_repo_url}//${local.context_base_path}?ref=${var.iam_policy_branch}" : (var.repo_root_path != "" ? "${var.repo_root_path}/${local.context_base_path}" : "${path.root}/${local.context_base_path}")
  hub_path     = local.use_git_urls ? "${var.iam_policy_repo_url}//${local.hub_base_path}?ref=${var.iam_policy_branch}" : (var.repo_root_path != "" ? "${var.repo_root_path}/${local.hub_base_path}" : "${path.root}/${local.hub_base_path}")

  # Check if context-specific files exist (only for local paths, not Git URLs)
  # fileexists() doesn't work with Git URLs, so we use try() to detect file presence
  has_context_inline_policy   = var.context != "hub" && !local.use_git_urls ? fileexists("${local.context_path}/source-policy-inline.json") : false
  has_context_arn_policy      = var.context != "hub" && !local.use_git_urls ? fileexists("${local.context_path}/source-policy-arn.json") : false
  has_context_override_policy = var.context != "hub" && !local.use_git_urls ? fileexists("${local.context_path}/overridepolicy.json") : false

  # Check if hub files exist (only for local paths)
  has_hub_inline_policy   = !local.use_git_urls ? fileexists("${local.hub_path}/source-policy-inline.json") : false
  has_hub_arn_policy      = !local.use_git_urls ? fileexists("${local.hub_path}/source-policy-arn.json") : false
  has_hub_override_policy = !local.use_git_urls ? fileexists("${local.hub_path}/overridepolicy.json") : false

  # Determine which path to use (context if exists, otherwise hub)
  use_inline_path   = local.has_context_inline_policy ? local.context_path : local.hub_path
  use_arn_path      = local.has_context_arn_policy ? local.context_path : local.hub_path
  use_override_path = local.has_context_override_policy ? local.context_path : local.hub_path

  # Load inline policy (context or hub or custom)
  # For Git URLs: always try to load from hub (context override not supported with Git)
  # For local paths: use fileexists() to determine which path to use
  has_inline_policy_file = local.use_git_urls ? true : (local.has_context_inline_policy || local.has_hub_inline_policy)
  filesystem_inline_policy = local.has_inline_policy_file ? try(file("${local.use_inline_path}/source-policy-inline.json"), null) : null
  final_inline_policy      = var.custom_inline_policy != null ? var.custom_inline_policy : local.filesystem_inline_policy

  # Load managed policy ARNs (context or hub or custom)
  has_arn_policy_file   = local.use_git_urls ? true : (local.has_context_arn_policy || local.has_hub_arn_policy)
  filesystem_policy_arns = local.has_arn_policy_file ? try(jsondecode(file("${local.use_arn_path}/source-policy-arn.json")), {}) : {}
  final_policy_arns      = length(var.custom_managed_arns) > 0 ? var.custom_managed_arns : local.filesystem_policy_arns

  # Load override policy (context or hub or custom)
  has_override_policy_file = local.use_git_urls ? true : (local.has_context_override_policy || local.has_hub_override_policy)
  filesystem_override_policy = local.has_override_policy_file ? try(file("${local.use_override_path}/overridepolicy.json"), null) : null
  final_override_policy      = var.custom_override_policy != null ? var.custom_override_policy : local.filesystem_override_policy

  # Build output lists
  override_policy_documents = local.final_override_policy != null ? [local.final_override_policy] : []
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
  description = "Source of the policy (filesystem, custom, or none)"
  value = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0 ? "custom" : (
    local.has_inline_policy_file || local.has_arn_policy_file ? "filesystem" : "none"
  )
}
