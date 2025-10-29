###############################################################################
# Data Sources
###############################################################################
data "google_client_config" "current" {}
data "google_project" "current" {
  project_id = var.project_id
}

###############################################################################
# Local Variables
###############################################################################
locals {
  spoke_service_account_emails_by_controller = {
    for controller_name in keys(var.addon_configs) : controller_name => compact([
      for spoke_alias, controllers in var.spoke_arn_inputs :
      try(controllers[controller_name].service_account_email, "")
    ])
  }
}

###############################################################################
# VPC Network Module
###############################################################################
module "vpc" {
  source = "../../../modules/gcp-vpc"

  create       = var.enable_vpc
  project_id   = var.project_id
  network_name = var.network_name != "" ? var.network_name : "${var.cluster_name}-network"
  routing_mode = "REGIONAL"

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
# GKE Cluster Module
###############################################################################
module "gke_cluster" {
  source = "../../../modules/gcp-gke-cluster"

  create                    = var.enable_vpc && var.enable_k8s_cluster
  project_id                = var.project_id
  cluster_name              = var.cluster_name
  location                  = var.region
  network                   = var.enable_vpc ? module.vpc.network_name : var.existing_vpc_id
  subnetwork                = var.enable_vpc ? module.vpc.subnet_names[0] : ""
  kubernetes_version        = var.cluster_version
  workload_identity_enabled = true

  node_pools = [
    {
      name         = "default-pool"
      machine_type = "e2-medium"
      min_count    = 1
      max_count    = 3
      disk_size_gb = 100
    }
  ]

  tags = merge(
    var.tags,
    var.k8s_cluster_tags,
    {
      caller = "csoc"
      module = "gke_cluster"
    }
  )

  depends_on = [module.vpc]
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
# Workload Identities Module (GCP equivalent of Pod Identities)
###############################################################################
module "workload_identities" {
  source = "../../../modules/gcp-workload-identity"

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

  project_id           = var.project_id
  service_account_name = "${var.cluster_name}-${each.value.service_name}"
  cluster_name         = var.cluster_name
  namespace            = each.value.namespace
  service_account_k8s  = each.value.service_account
  roles                = ["roles/viewer"]
  custom_role_id       = ""

  depends_on = [module.gke_cluster, module.iam_policies]
}

###############################################################################
# Cross Account Policy Module
# Note: GCP uses IAM bindings for cross-project access
# This is handled differently in GCP - IAM bindings are assigned to service accounts
###############################################################################
# GCP cross-project access is handled via service account IAM bindings
# which are managed in the spoke projects

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
              # Add GCP region annotation
              gcp_region = var.region
            },
            {
              # Create service account annotations for each addon
              for k, v in module.workload_identities :
              "${replace(k, "-", "")}_service_account" => lookup(var.addon_configs[k], "service_account", k)
            },
            {
              # Create hub service account email annotations
              for k, v in module.workload_identities :
              "${replace(k, "-", "")}_hub_sa_email" => v.service_account_email
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

  depends_on = [module.gke_cluster, module.workload_identities]
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
    for k, v in module.workload_identities : k => {
      role_arn              = "" # Not applicable for GCP
      role_name             = v.service_account_name
      policy_arn            = "" # Not applicable for GCP
      service_name          = k
      policy_source         = "csoc_internal"
      service_account_email = v.service_account_email
    }
  }

  # Hub configurations
  addon_configs = var.addon_configs

  # Hub cluster information
  cluster_info = {
    cluster_name              = var.cluster_name
    cluster_endpoint          = try(module.gke_cluster.cluster_endpoint, "")
    region                    = var.region
    account_id                = var.project_id
    cluster_version           = try(module.gke_cluster.cluster_version, "")
    oidc_provider             = "" # GCP uses different workload identity mechanism
    oidc_provider_arn         = "" # Not applicable for GCP
    cluster_security_group_id = "" # Not applicable for GCP
    vpc_id                    = var.enable_vpc ? module.vpc.network_name : var.existing_vpc_id
    private_subnets           = var.enable_vpc ? module.vpc.subnet_names : var.existing_subnet_ids
    public_subnets            = []
  }

  gitops_context = {
    hub_repo_url      = try(var.argocd_cluster.metadata.annotations.hub_repo_url, "")
    hub_repo_revision = try(var.argocd_cluster.metadata.annotations.hub_repo_revision, "main")
    hub_repo_basepath = try(var.argocd_cluster.metadata.annotations.hub_repo_basepath, "argocd")
    gcp_region        = var.region
  }

  spokes = {}

  depends_on = [module.gke_cluster, module.workload_identities, module.argocd]
}

