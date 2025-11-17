################################################################################
# Kubernetes Controller Requirements Module
#
# Cloud-agnostic module that creates controller infrastructure for any provider:
# - Namespaces (for addon/ACK/ASO/GCC controllers)
# - Service Accounts (for each controller with cloud-specific IAM annotations)
# - ConfigMaps (cross-account/subscription/project role mappings)
#
# Supports:
# - AWS: EKS Pod Identity (eks.amazonaws.com/role-arn)
# - Azure: Workload Identity (azure.workload.identity/client-id)
# - GCP: Workload Identity (iam.gke.io/gcp-service-account)
# - Multi-cloud: Controllers from different providers on same cluster
################################################################################

locals {
  #############################################################################
  # Namespace Map - One entry per controller (including argocd)
  # Simplified: No special annotations or labels, just the name
  #############################################################################
  namespaces = {
    for controller_name, config in var.controller_configs :
    controller_name => {
      name = config.namespace
    }
  }

  #############################################################################
  # Service Account Map - One entry per controller (excluding argocd)
  # ArgoCD service accounts are managed by the Helm chart
  # Cloud-agnostic with provider-specific IAM annotations
  #############################################################################
  service_accounts = {
    for controller_name, config in var.controller_configs :
    controller_name => {
      name             = config.service_account
      namespace        = config.namespace
      controller       = controller_name
      description      = "Service account for ${controller_name} controller"
      identity_arn     = lookup(config, "identity_arn", "")
      identity_type    = lookup(config, "identity_type", "aws") # aws, azure, gcp

      # Provider-specific annotations
      annotations = merge(
        {
          "description" = "Service account for ${controller_name} controller"
        },
        # AWS EKS Pod Identity annotation
        lookup(config, "identity_type", "aws") == "aws" && lookup(config, "identity_arn", "") != "" ? {
          "eks.amazonaws.com/role-arn" = config.identity_arn
        } : {},
        # Azure Workload Identity annotation
        lookup(config, "identity_type", "aws") == "azure" && lookup(config, "identity_arn", "") != "" ? {
          "azure.workload.identity/client-id" = config.identity_arn
        } : {},
        # GCP Workload Identity annotation
        lookup(config, "identity_type", "aws") == "gcp" && lookup(config, "identity_arn", "") != "" ? {
          "iam.gke.io/gcp-service-account" = config.identity_arn
        } : {},
        lookup(config, "extra_annotations", {}),
        var.annotations
      )
    }
    if controller_name != "argocd" # ArgoCD service accounts managed by Helm chart
  }

  #############################################################################
  # ConfigMap Map - Cross-account/subscription/project role mappings
  # Excludes argocd since it doesn't need cross-account role mappings
  #############################################################################
  configmaps = {
    for controller_name, spoke_roles in var.controller_spoke_roles :
    controller_name => {
      name      = "${controller_name}-crossaccount-role-map"
      namespace = try(var.controller_configs[controller_name].namespace, "default")

      # Build account/subscription/project to role/identity mapping
      # Try provider-specific fields in order: AWS, Azure, GCP
      account_role_map = {
        for spoke_alias, spoke_data in spoke_roles :
        # Key: account_id (AWS), subscription_id (Azure), or project_id (GCP)
        try(spoke_data.account_id, spoke_data.subscription_id, spoke_data.project_id, spoke_alias) =>
        # Value: role_arn (AWS), identity_id (Azure), or service_account_email (GCP)
        try(spoke_data.role_arn, spoke_data.identity_id, spoke_data.service_account_email, "")
        # Only include entries where we have both key and value
        if (
          (try(spoke_data.account_id, "") != "" && try(spoke_data.role_arn, "") != "") ||
          (try(spoke_data.subscription_id, "") != "" && try(spoke_data.identity_id, "") != "") ||
          (try(spoke_data.project_id, "") != "" && try(spoke_data.service_account_email, "") != "")
        )
      }
    }
    # Only create configmap if there are spoke roles and it's not argocd
    if length(lookup(var.controller_spoke_roles, controller_name, {})) > 0 && controller_name != "argocd"
  }
}

################################################################################
# Controller Namespaces
################################################################################
resource "kubernetes_namespace_v1" "controller" {
  for_each = var.create ? local.namespaces : {}

  metadata {
    name = each.value.name
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}

################################################################################
# Controller Service Accounts
################################################################################
resource "kubernetes_service_account_v1" "controller" {
  for_each = var.create ? local.service_accounts : {}

  metadata {
    name        = each.value.name
    namespace   = each.value.namespace
    annotations = each.value.annotations
  }

  depends_on = [kubernetes_namespace_v1.controller]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
      secret,
      image_pull_secret,
      automount_service_account_token,
    ]
  }
}

################################################################################
# Controller ConfigMaps - Cross-Account Role Mappings
################################################################################
resource "kubernetes_config_map_v1" "controller_configmap" {
  for_each = var.create ? local.configmaps : {}

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  data = {
    for account_id, role_arn in each.value.account_role_map :
    account_id => role_arn
  }

  depends_on = [kubernetes_namespace_v1.controller]

  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels,
    ]
  }
}
