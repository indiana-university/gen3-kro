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
        if !contains(["namespace", "service_account", "enable_identity", "enable"], config_key)
      }
    )
    if contains(keys(var.addon_configs), k)
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
    "cluster-info.yaml"   = local.cluster_info_map != null ? yamlencode(local.cluster_info_map) : yamlencode({})
    "gitops-context.yaml" = yamlencode(var.gitops_context)
  }
}

###############################################################################
# End of File
###############################################################################
