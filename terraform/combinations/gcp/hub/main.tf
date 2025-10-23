###############################################################################
# Data Sources
###############################################################################
data "google_client_config" "current" {}

###############################################################################
# Locals
###############################################################################
locals {
  context = "csoc"
}

###############################################################################
# VPC Network
###############################################################################
module "vpc" {
  source = "../../modules/gcp-vpc"

  create       = var.enable_vpc
  project_id   = var.project_id
  network_name = var.network_name != "" ? var.network_name : "${var.cluster_name}-network"

  subnets = [
    {
      subnet_name           = "${var.cluster_name}-subnet"
      subnet_ip             = "10.0.0.0/24"
      subnet_region         = var.region
      subnet_private_access = true
    }
  ]
}

###############################################################################
# GKE Cluster
###############################################################################
module "gke_cluster" {
  source = "../../modules/gcp-gke-cluster"

  create                     = var.enable_gke_cluster
  project_id                 = var.project_id
  cluster_name               = var.cluster_name
  location                   = var.region
  network                    = module.vpc.network_name
  subnetwork                 = module.vpc.subnet_names[0]
  kubernetes_version         = var.kubernetes_version
  workload_identity_enabled  = true
  tags                       = var.tags

  depends_on = [module.vpc]
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
  provider             = "gcp"
  iam_policy_base_path = var.iam_base_path
  repo_root_path       = var.iam_repo_root != "" ? var.iam_repo_root : "${path.root}/../../../.."
}

###############################################################################
# Workload Identities
###############################################################################
module "workload_identities" {
  source = "../../modules/gcp-workload-identity"

  for_each = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      namespace       = lookup(addon_config, "namespace", "default")
      service_account = lookup(addon_config, "service_account", addon_name)
      enabled         = lookup(addon_config, "enable_workload_identity", false)
    }
    if lookup(addon_config, "enable_workload_identity", false)
  }

  create               = each.value.enabled
  project_id           = var.project_id
  service_account_name = "${var.cluster_name}-${each.key}"
  cluster_name         = var.cluster_name
  namespace            = each.value.namespace
  service_account_k8s  = each.value.service_account

  depends_on = [module.gke_cluster]
}
