###################################################################################################################################################
# ACK IAM Policy Module
# Fetches and merges ACK recommended policies with custom overrides
###################################################################################################################################################

###################################################################################################################################################
# Data Sources - Fetch ACK Recommended Policies
###################################################################################################################################################
data "http" "recommended_policy_arn" {
  count = var.create ? 1 : 0
  url   = "https://raw.githubusercontent.com/aws-controllers-k8s/${var.service_name}-controller/main/config/iam/recommended-policy-arn"
}

data "http" "recommended_inline_policy" {
  count = var.create ? 1 : 0
  url   = "https://raw.githubusercontent.com/aws-controllers-k8s/${var.service_name}-controller/main/config/iam/recommended-inline-policy"
}

# User-provided override policy from URL (optional)
data "http" "override_policy" {
  count = var.create && var.override_policy_url != "" ? 1 : 0
  url   = var.override_policy_url
}

# Local file override policy (optional)
data "local_file" "override_policy" {
  count    = var.create && var.override_policy_path != "" ? 1 : 0
  filename = var.override_policy_path
}

###################################################################################################################################################
# Locals - Policy Resolution
###################################################################################################################################################
locals {
  # Determine source policy (from ACK repo)
  has_inline_policy = var.create && length(data.http.recommended_inline_policy) > 0 ? (
    can(jsondecode(data.http.recommended_inline_policy[0].response_body)) &&
    data.http.recommended_inline_policy[0].status_code == 200
  ) : false

  has_policy_arn = var.create && length(data.http.recommended_policy_arn) > 0 ? (
    data.http.recommended_policy_arn[0].status_code == 200 &&
    trimspace(data.http.recommended_policy_arn[0].response_body) != ""
  ) : false

  source_inline_policy = local.has_inline_policy ? trimspace(data.http.recommended_inline_policy[0].response_body) : null
  source_policy_arn    = local.has_policy_arn ? trimspace(data.http.recommended_policy_arn[0].response_body) : null

  # Determine override policy
  override_policy_json = var.create ? (
    var.override_policy_path != "" && length(data.local_file.override_policy) > 0 ? data.local_file.override_policy[0].content : (
      var.override_policy_url != "" && length(data.http.override_policy) > 0 ? data.http.override_policy[0].response_body : null
    )
  ) : null

  # Build policy documents list
  source_policy_documents   = local.source_inline_policy != null ? [local.source_inline_policy] : []
  override_policy_documents = local.override_policy_json != null ? [local.override_policy_json] : []

  # Managed policy ARNs
  recommended_policy_arns = local.source_policy_arn != null ? {
    ack_recommended = local.source_policy_arn
  } : {}

  # Merge with additional policy ARNs
  all_policy_arns = merge(local.recommended_policy_arns, var.additional_policy_arns)
}

###################################################################################################################################################
# IAM Policy Document (if inline policies are used)
###################################################################################################################################################
data "aws_iam_policy_document" "combined" {
  count = var.create && (length(local.source_policy_documents) > 0 || length(local.override_policy_documents) > 0) ? 1 : 0

  # Source policy documents
  source_policy_documents = local.source_policy_documents

  # Override policy documents
  override_policy_documents = local.override_policy_documents
}
###################################################################################################################################################
# End of File
###################################################################################################################################################
