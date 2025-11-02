################################################################################
# ArgoCD Cluster ConfigMap (Dynamic Configuration)
#
# This module creates a ConfigMap with dynamic cluster configuration that
# ArgoCD ApplicationSets can query for IAM roles, namespaces, and cluster info.
#
# ConfigMap Name: ${cluster_name}-argocd-settings
# Namespace: argocd (or var.argocd_namespace)
#
# Data Keys:
# - addons.yaml: Service configurations (namespace, serviceAccount, IAM roles, extra config)
# - cluster-info.yaml: EKS cluster details (endpoint, version, OIDC, VPC)
# - gitops-context.yaml: GitOps repository and spoke information
################################################################################

locals {
  # Build unified configuration map
  addons_map = {
    for k, v in var.pod_identities :
    k => merge(
      {
        namespace      = lookup(var.addon_configs[k], "namespace", k)
        serviceAccount = lookup(var.addon_configs[k], "service_account", k)
        roleArn        = v.role_arn
      },
      # Azure specific fields
      can(v.client_id) && v.client_id != "" ? {
        clientId = v.client_id
      } : {},
      can(v.principal_id) && v.principal_id != "" ? {
        principalId = v.principal_id
      } : {},
      # GCP specific fields
      can(v.service_account_email) && v.service_account_email != "" ? {
        serviceAccountEmail = v.service_account_email
      } : {},
      # Add extra configuration from addon_configs (KMS keys, etc.)
      {
        for config_key, config_val in var.addon_configs[k] :
        config_key => config_val
        if !contains([
          "namespace",
          "service_account",
          "enable_identity",
          "enable",
          "enabled",
          "enable_argocd",
          "argocd_chart_version",
          "create_permission",
          "attach_custom_policy",
          "kms_key_arns",
          "secrets_manager_arns",
          "ssm_parameter_arns",
          "parameter_store_arns",
          "inline_policy"
        ], config_key)
      }
    )
    if contains(keys(var.addon_configs), k)
  }

  # Build cluster info map - removed, now in cluster secret
  cluster_info_map = null
}

resource "kubernetes_config_map_v1" "argocd_cluster_config" {
  count = var.create && var.cluster_info != null ? 1 : 0

  metadata {
    name      = "${var.context}-argocd-settings"
    namespace = var.argocd_namespace

    labels = {
      cluster     = var.cluster_name
      context     = var.context
      config-type = "argocd-cluster"
    }
  }

  data = {
    "addons.yaml"         = yamlencode(local.addons_map)
    "gitops-context.yaml" = yamlencode(var.gitops_context)
  }
}

################################################################################
# Export ConfigMap to File (for reference/documentation)
################################################################################
locals {
  # Format ConfigMap as proper YAML
  configmap_yaml = <<-EOY
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${var.context}-argocd-settings
  namespace: ${var.argocd_namespace}
  labels:
    cluster: ${var.cluster_name}
    context: ${var.context}
    config-type: argocd-cluster
data:
  addons.yaml: |
    ${indent(4, yamlencode(local.addons_map))}
  gitops-context.yaml: |
    ${indent(4, yamlencode(var.gitops_context))}
EOY
}

resource "local_file" "argocd_configmap" {
  count    = var.create && var.cluster_info != null && var.outputs_dir != "" ? 1 : 0
  filename = "${var.outputs_dir}/configmap_${var.context}.yaml"
  content  = local.configmap_yaml

  depends_on = [kubernetes_config_map_v1.argocd_cluster_config]
}

###############################################################################
# End of File
###############################################################################
