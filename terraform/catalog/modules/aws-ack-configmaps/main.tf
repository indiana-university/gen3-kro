################################################################################
# Multi-Controller ACK Cross-Account Role ConfigMaps
#
# Creates ConfigMaps for all ACK controllers in their respective namespaces
# that map spoke account IDs to IAM role ARNs for cross-account resource management.
#
# ConfigMap Format (per controller):
#   name: <cluster_name>-ack-<controller_name>-crossaccount-role-map
#   namespace: <controller_name>-ns
#   data:
#     "<account_id>": "arn:aws:iam::<account_id>:role/<role_name>"
################################################################################

locals {
  # Build per-controller ConfigMaps from controller_spoke_roles input
  # Format: {
  #   "ack-s3" = {
  #     "spoke1" = { account_id = "111...", role_arn = "arn:..." }
  #   }
  # }
  # Filter out ArgoCD since it manages its own namespace
  configmaps = {
    for controller_name, spoke_roles in var.controller_spoke_roles :
    controller_name => {
      namespace = "${controller_name}-ns"
      account_role_map = {
        for spoke_alias, spoke_data in spoke_roles :
        spoke_data.account_id => spoke_data.role_arn
        if try(spoke_data.account_id, "") != "" && try(spoke_data.role_arn, "") != ""
      }
    }
    if length({
      for spoke_alias, spoke_data in spoke_roles :
      spoke_data.account_id => spoke_data.role_arn
      if try(spoke_data.account_id, "") != "" && try(spoke_data.role_arn, "") != ""
    }) > 0 && (startswith(controller_name, "ack-") || startswith(controller_name, "external"))
  }
}

################################################################################
# Kubernetes Namespaces for ACK Controllers
################################################################################
resource "kubernetes_namespace_v1" "ack_controller_namespaces" {
  for_each = var.create ? local.configmaps : {}

  metadata {
    name = replace(each.value.namespace, "_", "-")

    labels = {
      "app.kubernetes.io/part-of"    = "gen3-kro"
      "app.kubernetes.io/component"  = "ack-controller"
      "app.kubernetes.io/controller" = replace(each.key, "_", "-")
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

################################################################################
# Per-Controller ConfigMaps for ACK Cross-Account Role Mapping
################################################################################
resource "kubernetes_config_map_v1" "ack_controller_cross_account_role_configmap" {
  for_each = var.create ? local.configmaps : {}

  depends_on = [kubernetes_namespace_v1.ack_controller_namespaces]

  metadata {
    name      = "${var.cluster_name}-ack-${replace(each.key, "_", "-")}-crossaccount-role-map"
    namespace = replace(each.value.namespace, "_", "-")

    labels = {
      "app.kubernetes.io/name"       = "${var.cluster_name}-ack-${replace(each.key, "_", "-")}-crossaccount-role-map"
      "app.kubernetes.io/part-of"    = "gen3-kro"
      "app.kubernetes.io/component"  = "ack-controller"
      "app.kubernetes.io/controller" = replace(each.key, "_", "-")
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/instance"   = var.cluster_name
    }
  }

  data = each.value.account_role_map
}
