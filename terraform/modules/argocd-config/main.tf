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
# - ack.yaml: ACK controller configurations (namespace, serviceAccount, IAM roles)
# - addons.yaml: Addon configurations (namespace, serviceAccount, IAM roles, extra config)
# - cluster-info.yaml: EKS cluster details (endpoint, version, OIDC, VPC)
# - gitops-context.yaml: GitOps repository and spoke information
################################################################################

locals {
  # Build ACK controllers configuration map
  ack_controllers_map = {
    for k, v in var.pod_identities :
    replace(k, "ack-", "") => {
      enabled        = true
      namespace      = lookup(var.ack_configs[replace(k, "ack-", "")], "namespace", "ack-system")
      serviceAccount = lookup(var.ack_configs[replace(k, "ack-", "")], "service_account", "ack-${replace(k, "ack-", "")}-controller")
      hubRoleArn     = v.role_arn
      policyArn      = v.policy_arn
      # Add spoke role ARNs if configured
      spokes = {
        for spoke_alias, spoke_data in var.spokes :
        spoke_alias => try(spoke_data.role_arns[replace(k, "ack-", "")], "")
      }
    }
    if startswith(k, "ack-") && contains(keys(var.ack_configs), replace(k, "ack-", ""))
  }

  # Build addons configuration map
  # Addons use direct names (no "addon-" prefix in keys)
  addons_map = {
    for k, v in var.pod_identities :
    k => merge(
      {
        enabled        = true
        namespace      = lookup(var.addon_configs[k], "namespace", k)
        serviceAccount = lookup(var.addon_configs[k], "service_account", k)
        roleArn        = v.role_arn
        policyArn      = v.policy_arn
      },
      # Add extra configuration from addon_configs (KMS keys, etc.)
      {
        for config_key, config_val in var.addon_configs[k] :
        config_key => config_val
        if !contains(["namespace", "service_account", "enable_pod_identity", "enable"], config_key)
      }
    )
    if !startswith(k, "ack-") && contains(keys(var.addon_configs), k)
  }

  # Build cluster info map
  cluster_info_map = var.cluster_info != null ? {
    name      = var.cluster_info.cluster_name
    server    = var.cluster_info.cluster_endpoint
    region    = var.cluster_info.region
    accountId = var.cluster_info.account_id
    eks = {
      version                = var.cluster_info.cluster_version
      endpoint               = var.cluster_info.cluster_endpoint
      oidcProvider           = var.cluster_info.oidc_provider
      oidcProviderArn        = var.cluster_info.oidc_provider_arn
      clusterSecurityGroupId = try(var.cluster_info.cluster_security_group_id, "")
    }
    vpc = {
      vpcId          = try(var.cluster_info.vpc_id, "")
      privateSubnets = try(var.cluster_info.private_subnets, [])
      publicSubnets  = try(var.cluster_info.public_subnets, [])
    }
  } : null
}

resource "kubernetes_config_map_v1" "argocd_cluster_config" {
  count = var.create && var.cluster_info != null ? 1 : 0

  metadata {
    name      = "${var.cluster_name}-argocd-settings"
    namespace = var.argocd_namespace

    labels = {
      cluster     = var.cluster_name
      config-type = "argocd-cluster"
    }
  }

  data = {
    "ack.yaml"            = yamlencode(local.ack_controllers_map)
    "addons.yaml"         = yamlencode(local.addons_map)
    "cluster-info.yaml"   = local.cluster_info_map != null ? yamlencode(local.cluster_info_map) : yamlencode({})
    "gitops-context.yaml" = yamlencode(var.gitops_context)
  }
}
