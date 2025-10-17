###################################################################################################################################################
# Enhanced ACK Pod Identity Module
# Creates pod identity for ACK services with automatic policy loading and cross-account merging
###################################################################################################################################################

###################################################################################################################################################
# Local Configuration
###################################################################################################################################################
locals {
  # Determine context from tags (hub or spoke)
  context = lookup(var.tags, "Spoke", null) != null ? lookup(var.tags, "Spoke") : "hub"

  # Build paths for policy files
  # Try spoke-specific path first, then fall back to hub
  spoke_path = "${path.root}/../../../../../../../terraform/combinations/iam/gen3-kro/${local.context}/acks/${var.service_name}"
  hub_path   = "${path.root}/../../../../../../../terraform/combinations/iam/gen3-kro/hub/acks/${var.service_name}"

  # Check if spoke-specific inline policy exists
  has_spoke_inline_policy = local.context != "hub" ? fileexists("${local.spoke_path}/source-policy-inline.json") : false
  has_hub_inline_policy   = fileexists("${local.hub_path}/source-policy-inline.json")

  # Check if spoke-specific ARN policy exists
  has_spoke_arn_policy = local.context != "hub" ? fileexists("${local.spoke_path}/source-policy-arn.json") : false
  has_hub_arn_policy   = fileexists("${local.hub_path}/source-policy-arn.json")

  # Check if spoke-specific override policy exists
  has_spoke_override_policy = local.context != "hub" ? fileexists("${local.spoke_path}/overridepolicy.json") : false
  has_hub_override_policy   = fileexists("${local.hub_path}/overridepolicy.json")

  # Determine which path to use (spoke if exists, otherwise hub)
  use_inline_path   = local.has_spoke_inline_policy ? local.spoke_path : local.hub_path
  use_arn_path      = local.has_spoke_arn_policy ? local.spoke_path : local.hub_path
  use_override_path = local.has_spoke_override_policy ? local.spoke_path : local.hub_path

  # Load inline policy (spoke or hub)
  has_inline_policy_file = local.has_spoke_inline_policy || local.has_hub_inline_policy
  local_inline_policy    = local.has_inline_policy_file ? file("${local.use_inline_path}/source-policy-inline.json") : null

  # Load policy ARNs (spoke or hub)
  has_arn_policy_file = local.has_spoke_arn_policy || local.has_hub_arn_policy
  local_policy_arns   = local.has_arn_policy_file ? jsondecode(file("${local.use_arn_path}/source-policy-arn.json")) : {}

  # Load override policy (spoke or hub)
  has_override_policy_file = local.has_spoke_override_policy || local.has_hub_override_policy
  local_override_policy    = local.has_override_policy_file ? file("${local.use_override_path}/overridepolicy.json") : null

  # Build policy documents list (include cross-account policy if provided)
  source_policy_documents = compact([
    local.local_inline_policy,
    var.cross_account_policy_json
  ])

  # Build override policy documents list
  override_policy_documents = compact(concat(
    var.override_policy_documents,
    local.local_override_policy != null ? [local.local_override_policy] : []
  ))

  # Merge with additional policy ARNs
  all_policy_arns = merge(local.local_policy_arns, var.additional_policy_arns)

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
