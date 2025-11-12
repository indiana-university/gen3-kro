###############################################################################
# AWS Pod Identity Module
# Universal wrapper for EKS Pod Identity supporting ACK, addons, ArgoCD, and
# custom services. Uses the terraform-aws-modules/eks-pod-identity/aws module.
# IAM policies are pre-loaded by caller and passed in.
###############################################################################

###############################################################################
# Local Variables
# Compute policy sources and determine context
###############################################################################
locals {
  # Determine context from tags (hub or spoke)
  context = lookup(var.tags, "Spoke", null) != null ? lookup(var.tags, "Spoke") : var.context

  use_custom_policies = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0
  use_loaded_policies = !local.use_custom_policies && var.has_loaded_inline_policy

  source_policy_documents = local.use_custom_policies ? (
    var.custom_inline_policy != null ? [var.custom_inline_policy] : []
    ) : (
    local.use_loaded_policies && var.loaded_inline_policy_document != null ? [var.loaded_inline_policy_document] : []
  )

  all_source_policy_documents = compact(concat(
    local.source_policy_documents,
    var.cross_account_policy_json != null ? [var.cross_account_policy_json] : []
  ))

  override_policy_documents = local.use_custom_policies ? [] : var.loaded_override_policy_documents

  loaded_policy_arns     = local.use_loaded_policies ? var.loaded_managed_policy_arns : {}
  custom_policy_arns     = local.use_custom_policies ? var.custom_managed_arns : {}
  additional_policy_arns = merge(local.loaded_policy_arns, local.custom_policy_arns, var.additional_policy_arns)

  has_inline_policy = length(local.all_source_policy_documents) > 0 || length(local.override_policy_documents) > 0

  # Build associations map
  # If spoke_associations is provided, use it (multi-spoke mode)
  # Otherwise, use single namespace/service_account (legacy mode)
  associations = length(var.spoke_associations) > 0 ? {
    for spoke_key, spoke_config in var.spoke_associations : spoke_key => {
      cluster_name    = var.cluster_name
      namespace       = spoke_config.namespace
      service_account = "${spoke_config.spoke_alias}-${spoke_config.service_account}"
    }
  } : (
    var.namespace != "" && var.service_account != "" ? {
      csoc-cluster = {
        cluster_name    = var.cluster_name
        namespace       = var.namespace
        service_account = var.service_account
      }
    } : {}
  )
}

###############################################################################
# Pod Identity Module
# Creates IAM role and EKS pod identity association
###############################################################################
module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.2.0"

  count = var.create ? 1 : 0

  name            = "${var.cluster_name}-${var.service_name}"
  use_name_prefix = false

  attach_custom_policy      = local.has_inline_policy
  source_policy_documents   = local.all_source_policy_documents
  override_policy_documents = local.override_policy_documents

  additional_policy_arns = local.additional_policy_arns

  trust_policy_conditions = var.trust_policy_conditions

  associations = local.associations

  tags = var.tags
}

###############################################################################
# End of File
###############################################################################
