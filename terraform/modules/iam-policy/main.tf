###################################################################################################################################################
# Generic IAM Policy Module - Main Logic
###################################################################################################################################################

locals {
  # Build paths for policy files
  # Pattern: {base_path}/gen3-kro/{context}/{service_type}/{service_name}/
  context_base_path = "${var.iam_policy_base_path}/gen3-kro/${var.context}/${var.service_type}/${var.service_name}"
  hub_base_path     = "${var.iam_policy_base_path}/gen3-kro/hub/${var.service_type}/${var.service_name}"

  # HTTP URLs for fetching from GitHub raw content
  use_http = var.iam_raw_base_url != ""
  http_hub_path = local.use_http ? "${var.iam_raw_base_url}/${local.hub_base_path}" : ""

  # Local filesystem paths as fallback
  local_context_path = var.repo_root_path != "" ? "${var.repo_root_path}/${local.context_base_path}" : "${path.root}/${local.context_base_path}"
  local_hub_path     = var.repo_root_path != "" ? "${var.repo_root_path}/${local.hub_base_path}" : "${path.root}/${local.hub_base_path}"
}

###################################################################################################################################################
# HTTP Data Sources - Fetch policies from GitHub raw content URLs (primary source)
###################################################################################################################################################
data "http" "inline_policy" {
  count = local.use_http ? 1 : 0
  url   = "${local.http_hub_path}/source-policy-inline.json"

  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 || self.status_code == 404
      error_message = "HTTP request failed with status ${self.status_code}"
    }
  }
}

data "http" "managed_arns" {
  count = local.use_http ? 1 : 0
  url   = "${local.http_hub_path}/source-policy-arn.json"

  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 || self.status_code == 404
      error_message = "HTTP request failed with status ${self.status_code}"
    }
  }
}

data "http" "override_policy" {
  count = local.use_http ? 1 : 0
  url   = "${local.http_hub_path}/overridepolicy.json"

  request_headers = {
    Accept = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 || self.status_code == 404
      error_message = "HTTP request failed with status ${self.status_code}"
    }
  }
}

locals {
  # Extract HTTP responses (null if 404 or not using HTTP)
  http_inline_policy   = local.use_http && try(data.http.inline_policy[0].status_code, 0) == 200 ? data.http.inline_policy[0].response_body : null
  http_managed_arns    = local.use_http && try(data.http.managed_arns[0].status_code, 0) == 200 ? try(jsondecode(data.http.managed_arns[0].response_body), {}) : {}
  http_override_policy = local.use_http && try(data.http.override_policy[0].status_code, 0) == 200 ? data.http.override_policy[0].response_body : null

  # Filesystem fallback - only try if HTTP didn't succeed
  fs_inline_policy   = local.http_inline_policy == null ? try(file("${local.local_hub_path}/source-policy-inline.json"), null) : null
  fs_managed_arns    = length(local.http_managed_arns) == 0 ? try(jsondecode(file("${local.local_hub_path}/source-policy-arn.json")), {}) : {}
  fs_override_policy = local.http_override_policy == null ? try(file("${local.local_hub_path}/overridepolicy.json"), null) : null

  # Final policies (custom > http > filesystem)
  final_inline_policy   = var.custom_inline_policy != null ? var.custom_inline_policy : (local.http_inline_policy != null ? local.http_inline_policy : local.fs_inline_policy)
  final_policy_arns     = length(var.custom_managed_arns) > 0 ? var.custom_managed_arns : (length(local.http_managed_arns) > 0 ? local.http_managed_arns : local.fs_managed_arns)
  final_override_policy = var.custom_override_policy != null ? var.custom_override_policy : (local.http_override_policy != null ? local.http_override_policy : local.fs_override_policy)

  # Build output lists
  override_policy_documents = local.final_override_policy != null ? [local.final_override_policy] : []

  # Track actual source used (custom, git, filesystem, or none)
  actual_source = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0 ? "custom" : (
    local.http_inline_policy != null || length(local.http_managed_arns) > 0 ? "git" : (
      local.fs_inline_policy != null || length(local.fs_managed_arns) > 0 ? "filesystem" : "none"
    )
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
    http_hub_path       = local.http_hub_path
    local_hub_path      = local.local_hub_path
    repo_root_path      = var.repo_root_path
    service_type        = var.service_type
    service_name        = var.service_name
    http_inline_found   = local.http_inline_policy != null
    fs_inline_found     = local.fs_inline_policy != null
    final_inline_found  = local.final_inline_policy != null
    policy_source       = local.actual_source
  }
}
