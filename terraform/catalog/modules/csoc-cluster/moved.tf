################################################################################
# Compatibility-wrapper state moves
#
# These moved blocks preserve the current composite-state migration path while
# csoc-cluster delegates to the split foundation and in-cluster modules.
################################################################################

moved {
  from = module.aws_csoc.module.eks
  to   = module.aws_csoc_foundation.module.eks
}

moved {
  from = module.aws_csoc.module.vpc
  to   = module.aws_csoc_foundation.module.vpc
}

moved {
  from = module.aws_csoc.module.external_secrets_pod_identity
  to   = module.aws_csoc_foundation.module.external_secrets_pod_identity
}

moved {
  from = module.aws_csoc.aws_iam_role.ack_csoc_source
  to   = module.aws_csoc_foundation.aws_iam_role.ack_csoc_source
}

moved {
  from = module.aws_csoc.aws_eks_access_entry.ack_csoc_source
  to   = module.aws_csoc_foundation.aws_eks_access_entry.ack_csoc_source
}

moved {
  from = module.aws_csoc.aws_eks_access_policy_association.ack_csoc_source_admin
  to   = module.aws_csoc_foundation.aws_eks_access_policy_association.ack_csoc_source_admin
}

moved {
  from = module.aws_csoc.aws_eks_capability.ack
  to   = module.aws_csoc_foundation.aws_eks_capability.ack
}

moved {
  from = module.aws_csoc.aws_iam_role_policy.ack_csoc_assume_spoke
  to   = module.aws_csoc_foundation.aws_iam_role_policy.ack_csoc_assume_spoke
}

moved {
  from = module.aws_csoc.aws_iam_role.kro_controller
  to   = module.aws_csoc_foundation.aws_iam_role.kro_controller
}

moved {
  from = module.aws_csoc.aws_eks_access_entry.kro_controller
  to   = module.aws_csoc_foundation.aws_eks_access_entry.kro_controller
}

moved {
  from = module.aws_csoc.aws_eks_access_policy_association.kro_controller_admin
  to   = module.aws_csoc_foundation.aws_eks_access_policy_association.kro_controller_admin
}

moved {
  from = module.aws_csoc.aws_eks_capability.kro
  to   = module.aws_csoc_foundation.aws_eks_capability.kro
}

moved {
  from = module.aws_csoc.aws_iam_role.argocd_controller
  to   = module.aws_csoc_foundation.aws_iam_role.argocd_controller
}

moved {
  from = module.aws_csoc.aws_eks_access_entry.argocd_controller
  to   = module.aws_csoc_foundation.aws_eks_access_entry.argocd_controller
}

moved {
  from = module.aws_csoc.aws_eks_access_policy_association.argocd_controller_admin
  to   = module.aws_csoc_foundation.aws_eks_access_policy_association.argocd_controller_admin
}

moved {
  from = module.aws_csoc.aws_eks_capability.argocd
  to   = module.aws_csoc_foundation.aws_eks_capability.argocd
}

moved {
  from = module.aws_csoc.aws_iam_role.argocd_self_managed
  to   = module.aws_csoc_foundation.aws_iam_role.argocd_self_managed
}

moved {
  from = module.aws_csoc.aws_iam_role_policy.argocd_assume_spoke
  to   = module.aws_csoc_foundation.aws_iam_role_policy.argocd_assume_spoke
}

moved {
  from = module.aws_csoc.aws_iam_role_policy.argocd_inline
  to   = module.aws_csoc_foundation.aws_iam_role_policy.argocd_inline
}

moved {
  from = module.aws_csoc.kubernetes_namespace_v1.argocd
  to   = module.csoc_in_cluster_bootstrap.kubernetes_namespace_v1.argocd
}

moved {
  from = module.aws_csoc.kubernetes_service_account_v1.argocd
  to   = module.csoc_in_cluster_bootstrap.kubernetes_service_account_v1.argocd
}

moved {
  from = module.aws_csoc.kubernetes_service_account_v1.argocd_controller
  to   = module.csoc_in_cluster_bootstrap.kubernetes_service_account_v1.argocd_controller
}

moved {
  from = module.aws_csoc.helm_release.argocd
  to   = module.csoc_in_cluster_bootstrap.helm_release.argocd
}

moved {
  from = module.argocd_bootstrap
  to   = module.csoc_in_cluster_bootstrap.module.argocd_bootstrap
}
