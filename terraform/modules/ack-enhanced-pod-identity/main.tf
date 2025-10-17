###################################################################################################################################################
# Enhanced ACK Pod Identity Module
# Creates pod identity for ACK services with automatic policy loading and cross-account merging
###################################################################################################################################################

###################################################################################################################################################
# Local Configuration
###################################################################################################################################################
locals {
  # Path to ACK permissions
  ack_permissions_path = "${path.root}/../../iam/ack-permissions/${var.service_name}"

  # Check if local policy files exist
  has_local_inline_policy = fileexists("${local.ack_permissions_path}/recommended-inline-policy")
  has_local_policy_arn    = fileexists("${local.ack_permissions_path}/recommended-policy-arn")

  # Load local policies
  local_inline_policy = local.has_local_inline_policy ? file("${local.ack_permissions_path}/recommended-inline-policy") : null
  local_policy_arn    = local.has_local_policy_arn ? trimspace(file("${local.ack_permissions_path}/recommended-policy-arn")) : null

  # Build policy documents list (include cross-account policy if provided)
  source_policy_documents = compact([
    local.local_inline_policy,
    var.cross_account_policy_json
  ])

  override_policy_documents = var.override_policy_documents

  # Managed policy ARNs
  recommended_policy_arns = local.local_policy_arn != null ? {
    ack_recommended = local.local_policy_arn
  } : {}

  # Merge with additional policy ARNs
  all_policy_arns = merge(local.recommended_policy_arns, var.additional_policy_arns)

  # Determine if we have inline policies to attach
  has_inline_policy = length(local.source_policy_documents) > 0 || length(local.override_policy_documents) > 0
}

###################################################################################################################################################
# Pod Identity
###################################################################################################################################################
module "pod_identity" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name = "${var.cluster_name}-ack-${var.service_name}"

  # Attach custom policy if we have inline policies
  attach_custom_policy      = local.has_inline_policy
  source_policy_documents   = local.source_policy_documents
  override_policy_documents = local.override_policy_documents

  # Attach managed policy ARNs
  additional_policy_arns = local.all_policy_arns

  # Trust policy conditions
  trust_policy_conditions = var.trust_policy_conditions

  # Association defaults
  association_defaults = var.association_defaults

  # Pod Identity Associations
  associations = var.associations

  tags = var.tags
}
