###################################################################################################################################################
# ArgoCD Pod Identity Module
# Creates pod identity specifically for ArgoCD with cross-account and secrets access
###################################################################################################################################################

###################################################################################################################################################
# ArgoCD Pod Identity
###################################################################################################################################################
module "argocd_pod_identity" {
  count = var.create ? 1 : 0

  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.4.0"

  name            = "${var.cluster_name}-argocd-hub-mgmt"
  use_name_prefix = false

  # Attach custom policy if we have inline policies
  attach_custom_policy      = var.has_inline_policy
  source_policy_documents   = var.source_policy_documents
  override_policy_documents = var.override_policy_documents

  # Attach managed policy ARNs
  additional_policy_arns = var.policy_arns

  # Trust policy conditions for cross-account access
  trust_policy_conditions = var.trust_policy_conditions

  # Association defaults
  association_defaults = var.association_defaults

  # Pod Identity Associations for ArgoCD components
  associations = var.associations

  tags = var.tags
}
