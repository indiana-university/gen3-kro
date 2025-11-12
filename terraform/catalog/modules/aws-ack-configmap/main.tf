################################################################################
# Per-Controller ACK Cross-Account Role ConfigMaps
#
# Creates a ConfigMap per ACK controller in ack-system namespace that maps
# spoke account IDs to IAM role ARNs for cross-account resource management.
#
# ConfigMap Format:
#   name: <cluster_name>-ack-<controller_name>-crossaccount-role-map
#   namespace: ack-system
#   data:
#     "<account_id>": "arn:aws:iam::<account_id>:role/<role_name>"
################################################################################

locals {
  # Build per-controller account-to-role mapping from spoke_roles input
  # spoke_roles format: { "spoke1" = { account_id = "111...", role_arn = "arn:..." } }
  account_role_map = {
    for spoke_alias, spoke_data in var.spoke_roles :
    spoke_data.account_id => spoke_data.role_arn
    if try(spoke_data.account_id, "") != "" && try(spoke_data.role_arn, "") != ""
  }
}

################################################################################
# Per-Controller ConfigMap for ACK Cross-Account Role Mapping
################################################################################
resource "kubernetes_config_map_v1" "ack_controller_role_map" {
  count = var.create && length(local.account_role_map) > 0 ? 1 : 0

  metadata {
    name      = "${var.cluster_name}-ack-${var.controller_name}-crossaccount-role-map"
    namespace = var.configmap_namespace

    labels = merge(
      {
        "app.kubernetes.io/name"       = "${var.cluster_name}-ack-${var.controller_name}-crossaccount-role-map"
        "app.kubernetes.io/part-of"    = "gen3-kro"
        "app.kubernetes.io/component"  = "ack-controller"
        "app.kubernetes.io/controller" = var.controller_name
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.labels
    )
  }

  data = local.account_role_map
}

