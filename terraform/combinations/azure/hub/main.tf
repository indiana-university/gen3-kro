###############################################################################
# Data Sources
###############################################################################
data "azurerm_client_config" "current" {}

###############################################################################
# Locals
###############################################################################
locals {
  context = "csoc"
}

###############################################################################
# Resource Group
###############################################################################
module "resource_group" {
  source = "../../modules/azure-resource-group"

  create              = true
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

###############################################################################
# Virtual Network
###############################################################################
module "vnet" {
  source = "../../modules/azure-vnet"

  create              = var.enable_vnet
  vnet_name           = var.vnet_name != "" ? var.vnet_name : "${var.cluster_name}-vnet"
  resource_group_name = module.resource_group.resource_group_name
  location            = var.location
  address_space       = var.address_space
  subnet_names        = ["aks-subnet"]
  subnet_prefixes     = ["10.0.1.0/24"]
  tags                = var.tags

  depends_on = [module.resource_group]
}

###############################################################################
# AKS Cluster
###############################################################################
module "aks_cluster" {
  source = "../../modules/azure-aks-cluster"

  create                    = var.enable_aks_cluster
  cluster_name              = var.cluster_name
  resource_group_name       = module.resource_group.resource_group_name
  location                  = var.location
  kubernetes_version        = var.kubernetes_version
  dns_prefix                = var.cluster_name
  subnet_id                 = module.vnet.subnet_ids[0]
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                      = var.tags

  depends_on = [module.vnet]
}

###############################################################################
# IAM Policies
###############################################################################
module "iam_policies" {
  source = "../../modules/iam-policy"

  for_each = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => addon_config
    if lookup(addon_config, "enable_workload_identity", false)
  }

  service_name         = each.key
  context              = local.context
  provider             = "azure"
  iam_policy_base_path = var.iam_base_path
  repo_root_path       = var.iam_repo_root != "" ? var.iam_repo_root : "${path.root}/../../../.."
}

###############################################################################
# Managed Identities
###############################################################################
module "managed_identities" {
  source = "../../modules/azure-managed-identity"

  for_each = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      namespace       = lookup(addon_config, "namespace", "default")
      service_account = lookup(addon_config, "service_account", addon_name)
      enabled         = lookup(addon_config, "enable_workload_identity", false)
    }
    if lookup(addon_config, "enable_workload_identity", false)
  }

  create                  = each.value.enabled
  identity_name           = "${var.cluster_name}-${each.key}"
  resource_group_name     = module.resource_group.resource_group_name
  location                = var.location
  cluster_oidc_issuer_url = module.aks_cluster.oidc_issuer_url
  namespace               = each.value.namespace
  service_account         = each.value.service_account
  tags                    = var.tags

  depends_on = [module.aks_cluster]
}
