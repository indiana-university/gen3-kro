###################################################################################################################################################
# Generic Pod Identity Module
# Universal wrapper for EKS Pod Identity supporting ACK, addons, ArgoCD, and custom services
# Uses the terraform-aws-modules/eks-pod-identity/aws module with integrated IAM policy loading
###################################################################################################################################################

locals {
  # Determine context from tags (hub or spoke)
  context = lookup(var.tags, "Spoke", null) != null ? lookup(var.tags, "Spoke") : var.context

  # Use IAM policy module to load policies
  load_policies = var.create && (var.custom_inline_policy == null && length(var.custom_managed_arns) == 0)
}

###################################################################################################################################################
# IAM Policy Module - Load policies from filesystem or Git
###################################################################################################################################################
module "iam_policy" {
  source = "../iam-policy"

  count = local.load_policies ? 1 : 0

  service_type         = var.service_type
  service_name         = var.service_name
  context              = local.context
  iam_policy_repo_url  = var.iam_policy_repo_url
  iam_policy_branch    = var.iam_policy_branch
  iam_policy_base_path = var.iam_policy_base_path
  iam_raw_base_url     = var.iam_raw_base_url
  repo_root_path       = var.repo_root_path
}

locals {
  # Determine which policies to use (custom or loaded from filesystem)
  use_custom_policies = var.custom_inline_policy != null || length(var.custom_managed_arns) > 0

  # Source policy documents (inline policies)
  source_policy_documents = local.use_custom_policies ? (
    var.custom_inline_policy != null ? [var.custom_inline_policy] : []
  ) : (
    local.load_policies && try(module.iam_policy[0].has_inline_policy, false) ? [module.iam_policy[0].inline_policy_document] : []
  )

  # Add cross-account policy if provided
  all_source_policy_documents = compact(concat(
    local.source_policy_documents,
    var.cross_account_policy_json != null ? [var.cross_account_policy_json] : []
  ))

  # Override policy documents
  override_policy_documents = local.use_custom_policies ? [] : (
    local.load_policies ? try(module.iam_policy[0].override_policy_documents, []) : []
  )

  # Managed policy ARNs
  filesystem_policy_arns = local.load_policies ? try(module.iam_policy[0].managed_policy_arns, {}) : {}
  custom_policy_arns     = local.use_custom_policies ? var.custom_managed_arns : {}
  additional_policy_arns = merge(local.filesystem_policy_arns, local.custom_policy_arns, var.additional_policy_arns)

  # Determine if we have inline policies to attach
  has_inline_policy = length(local.all_source_policy_documents) > 0 || length(local.override_policy_documents) > 0
}

###################################################################################################################################################
# Pod Identity - terraform-aws-modules/eks-pod-identity/aws
###################################################################################################################################################
module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  count = var.create ? 1 : 0

  # Role name - format: {cluster_name}-{service_type}-{service_name}
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
    namespace       = var.namespace
    service_account = var.service_account
  }

  # Pod Identity Association
  associations = {
    default = {
      cluster_name = var.cluster_name
    }
  }

  tags = var.tags
}
