###############################################################################
# Data Sources
###############################################################################
data "azurerm_client_config" "current" {}

###############################################################################
# Local Variables
###############################################################################
locals {
  spoke_principal_ids_by_controller = {
    for controller_name in keys(var.addon_configs) : controller_name => compact([
      for spoke_alias, controllers in var.spoke_arn_inputs :
      try(controllers[controller_name].principal_id, "")
    ])
  }
}

###############################################################################
# Resource Group Module
###############################################################################
module "resource_group" {
  source = "../../../modules/azure-resource-group"

  create              = true
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

###############################################################################
# Virtual Network Module
###############################################################################
module "vnet" {
  source = "../../../modules/azure-vnet"

  create              = var.enable_vpc
  vnet_name           = var.vnet_name != "" ? var.vnet_name : "${var.cluster_name}-vnet"
  resource_group_name = module.resource_group.resource_group_name
  location            = var.location
  address_space       = var.address_space
  subnet_names        = ["aks-subnet"]
  subnet_prefixes     = ["10.0.1.0/24"]

  tags = merge(
    var.tags,
    var.vpc_tags,
    {
      caller = "csoc"
      module = "vnet"
    }
  )

  depends_on = [module.resource_group]
}

###############################################################################
# AKS Cluster Module
###############################################################################
module "aks_cluster" {
  source = "../../../modules/azure-aks-cluster"

  create                    = var.enable_vpc && var.enable_k8s_cluster
  cluster_name              = var.cluster_name
  resource_group_name       = module.resource_group.resource_group_name
  location                  = var.location
  kubernetes_version        = var.cluster_version
  dns_prefix                = var.cluster_name
  subnet_id                 = var.enable_vpc ? module.vnet.subnet_ids[0] : var.existing_vpc_id
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_plugin = "azure"

  default_node_pool = {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_D2s_v3"
  }

  tags = merge(
    var.tags,
    var.k8s_cluster_tags,
    {
      caller = "csoc"
      module = "aks_cluster"
    }
  )

  depends_on = [module.vnet]
}

###############################################################################
# IAM Policy Module - Load policies for Workload Identities
###############################################################################
module "iam_policies" {
  source = "../../../modules/iam-policy"

  for_each = var.csoc_iam_policies

  service_name       = each.key
  policy_inline_json = each.value
}

###############################################################################
# Managed Identities Module (Azure equivalent of Pod Identities)
###############################################################################
module "managed_identities" {
  source = "../../../modules/azure-managed-identity"

  for_each = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      service_name    = addon_name
      namespace       = lookup(addon_config, "namespace", "kube-system")
      service_account = lookup(addon_config, "service_account", addon_name)
      enabled         = lookup(addon_config, "enable_identity", false)
    }
    if lookup(addon_config, "enable_identity", false)
  }

  create = var.enable_vpc && var.enable_k8s_cluster && each.value.enabled

  identity_name           = "${var.cluster_name}-${each.value.service_name}"
  resource_group_name     = module.resource_group.resource_group_name
  location                = var.location
  cluster_oidc_issuer_url = module.aks_cluster.oidc_issuer_url
  namespace               = each.value.namespace
  service_account         = each.value.service_account
  role_definition_id      = "b24988ac-6180-42a0-ab88-20f7382dd24c" # Contributor role
  scope                   = module.resource_group.resource_group_id

  tags = merge(
    var.tags,
    {
      caller       = "csoc"
      module       = "managed_identities"
      service_name = each.value.service_name
      context      = var.csoc_alias
    }
  )

  depends_on = [module.aks_cluster, module.iam_policies]
}

###############################################################################
# Cross Account Policy Module
# Note: Azure uses RBAC role assignments instead of policies
# This is handled differently in Azure - roles are assigned to managed identities
###############################################################################
# Azure cross-account access is handled via Azure AD B2B and role assignments
# which are managed separately from the managed identity creation

###############################################################################
locals {
  argocd_cluster_enhanced = merge(
    var.argocd_cluster,
    {
      metadata = merge(
        lookup(var.argocd_cluster, "metadata", {}),
        {
          annotations = merge(
            lookup(lookup(var.argocd_cluster, "metadata", {}), "annotations", {}),
            {
              # Add Azure region annotation
              azure_region = var.location
            },
            {
              # Create service account annotations for each addon
              for k, v in module.managed_identities :
              "${replace(k, "-", "_")}_service_account" => lookup(var.addon_configs[k], "service_account", k)
            },
            {
              # Create hub identity client ID annotations
              for k, v in module.managed_identities :
              "${replace(k, "-", "")}_hub_client_id" => v.client_id
            },
          )
        }
      )
    }
  )

  argocd_config_enhanced = merge(
    var.argocd_config,
    {
      values = [file("${path.module}/../bootstrap/argocd-initial-values.yaml")]
    }
  )

  argocd_apps_enhanced = merge(
    {
      bootstrap = file("${path.module}/../bootstrap/applicationsets.yaml")
    },
    var.argocd_apps
  )
}

###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "../../../modules/argocd"

  create = var.enable_vpc && var.enable_k8s_cluster && var.enable_argocd

  argocd      = local.argocd_config_enhanced
  install     = var.argocd_install
  cluster     = local.argocd_cluster_enhanced
  apps        = local.argocd_apps_enhanced
  outputs_dir = var.argocd_outputs_dir

  depends_on = [module.aks_cluster, module.managed_identities]
}

###############################################################################
# Hub ConfigMap
###############################################################################
module "hub_configmap" {
  source = "../../../modules/spokes-configmap"

  create           = var.enable_vpc && var.enable_k8s_cluster && var.enable_argocd
  context          = var.csoc_alias
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  pod_identities = {
    for k, v in module.managed_identities : k => {
      role_arn      = "" # Not applicable for Azure
      role_name     = v.identity_name
      policy_arn    = "" # Not applicable for Azure
      service_name  = k
      policy_source = "csoc_internal"
      principal_id  = v.principal_id
      client_id     = v.client_id
    }
  }

  # Hub configurations
  addon_configs = var.addon_configs

  # Hub cluster information
  cluster_info = {
    cluster_name              = var.cluster_name
    cluster_endpoint          = try(module.aks_cluster.cluster_endpoint, "")
    region                    = var.location
    account_id                = try(data.azurerm_client_config.current.subscription_id, "")
    cluster_version           = try(module.aks_cluster.cluster_version, "")
    oidc_provider             = try(module.aks_cluster.oidc_issuer_url, "")
    oidc_provider_arn         = "" # Not applicable for Azure
    cluster_security_group_id = "" # Not applicable for Azure
    vpc_id                    = var.enable_vpc ? module.vnet.vnet_id : var.existing_vpc_id
    private_subnets           = var.enable_vpc ? module.vnet.subnet_ids : var.existing_subnet_ids
    public_subnets            = []
  }

  gitops_context = {
    hub_repo_url      = try(var.argocd_cluster.metadata.annotations.hub_repo_url, "")
    hub_repo_revision = try(var.argocd_cluster.metadata.annotations.hub_repo_revision, "main")
    hub_repo_basepath = try(var.argocd_cluster.metadata.annotations.hub_repo_basepath, "argocd")
    azure_region      = var.location
  }

  spokes = {}

  depends_on = [module.aks_cluster, module.managed_identities, module.argocd]
}

