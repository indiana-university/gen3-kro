################################################################################
# Spoke Requirements Module (Cloud Agnostic)
#
# Combined module that creates all spoke infrastructure:
# - Namespaces (for each spoke infrastructure deployment)
# - ConfigMap (spokes charter for ArgoCD ApplicationSet templating)
#
# Supports AWS, Azure, and GCP with provider-specific annotations
################################################################################

locals {

  #############################################################################
  # Namespace Map - One entry per spoke (only if enabled)
  # Annotations determined by presence of account_id/subscription_id/project_id
  #############################################################################
  namespaces = {
    for spoke in var.spokes :
    spoke.alias => {
      name  = "${spoke.alias}-infrastructure"
      alias = spoke.alias
      # Provider-specific annotations - detect from spoke_identity_mappings
      annotations = try(var.spoke_identity_mappings[spoke.alias].account_id, null) != null ? merge({
        "services.k8s.aws/owner-account-id" = var.spoke_identity_mappings[spoke.alias].account_id
        "services.k8s.aws/default-region"   = try(spoke.provider.region, var.default_region)
        }, {}) : try(var.spoke_identity_mappings[spoke.alias].subscription_id, null) != null ? {
        "azure.workload.identity/subscription-id" = var.spoke_identity_mappings[spoke.alias].subscription_id
        } : try(var.spoke_identity_mappings[spoke.alias].project_id, null) != null ? {
        "iam.gke.io/project-id" = var.spoke_identity_mappings[spoke.alias].project_id
      } : {}
    }
    if lookup(spoke, "enabled", true)
  }
}

################################################################################
# Spoke Infrastructure Namespaces
################################################################################
resource "kubernetes_namespace_v1" "spoke_infrastructure" {
  for_each = var.create ? local.namespaces : {}

  metadata {
    name        = each.value.name
    annotations = each.value.annotations
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }

  timeouts {
    delete = "40m"
  }
}
