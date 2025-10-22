###################################################################################################################################################
# Generic Pod Identity Module
# Universal wrapper for EKS Pod Identity supporting ACK, addons, ArgoCD, and custom services
# Uses the terraform-aws-modules/eks-pod-identity/aws module
# IAM policies are pre-loaded by caller and passed in
###################################################################################################################################################

locals {
  # Determine context from tags (hub or spoke)
  context = lookup(var.tags, "Spoke", null) != null ? lookup(var.tags, "Spoke") : var.context

  # Determine which policies to use (custom or pre-loaded)
  use_custom_policies = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0
  use_loaded_policies = !local.use_custom_policies && var.has_loaded_inline_policy

  # Source policy documents (inline policies)
  source_policy_documents = local.use_custom_policies ? (
    var.custom_inline_policy != null ? [var.custom_inline_policy] : []
  ) : (
    local.use_loaded_policies && var.loaded_inline_policy_document != null ? [var.loaded_inline_policy_document] : []
  )

  # Add cross-account policy if provided
  all_source_policy_documents = compact(concat(
    local.source_policy_documents,
    var.cross_account_policy_json != null ? [var.cross_account_policy_json] : []
  ))

  # Override policy documents
  override_policy_documents = local.use_custom_policies ? [] : var.loaded_override_policy_documents

  # Managed policy ARNs
  loaded_policy_arns     = local.use_loaded_policies ? var.loaded_managed_policy_arns : {}
  custom_policy_arns     = local.use_custom_policies ? var.custom_managed_arns : {}
  additional_policy_arns = merge(local.loaded_policy_arns, local.custom_policy_arns, var.additional_policy_arns)

  # Determine if we have inline policies to attach
  has_inline_policy = length(local.all_source_policy_documents) > 0 || length(local.override_policy_documents) > 0
}

###################################################################################################################################################
# Pod Identity - terraform-aws-modules/eks-pod-identity/aws
###################################################################################################################################################
module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.2.0"

  count = var.create ? 1 : 0

  # Role name - format: {cluster_name}-{service_name}
  name            = "${var.cluster_name}-${var.service_name}"
  use_name_prefix = false  # Use exact name, don't add random suffix

  # Attach custom policy if we have inline policies
  attach_custom_policy      = local.has_inline_policy
  source_policy_documents   = local.all_source_policy_documents
  override_policy_documents = local.override_policy_documents

  # Attach managed policy ARNs
  additional_policy_arns = local.additional_policy_arns

  # Trust policy conditions
  trust_policy_conditions = var.trust_policy_conditions

  # Association defaults
  association_defaults = {
    cluster_name    = var.cluster_name
    namespace       = var.namespace
    service_account = var.service_account
  }

  # Pod Identity Association - unique per service
  associations = {
    "${var.service_name}" = {}
  }

  tags = var.tags
}
