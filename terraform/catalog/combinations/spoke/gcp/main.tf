###############################################################################
# Local Variables
###############################################################################
locals {
  # Services that need roles created in the spoke project
  services_needing_roles = {
    for addon_name, addon_config in var.addon_configs :
    addon_name => {
      csoc_sa_email = lookup(var.csoc_pod_identity_arns, addon_name, "")
    }
    if lookup(addon_config, "enable_identity", false) &&
    lookup(var.csoc_pod_identity_arns, addon_name, "") != ""
  }

  # Services using override identities (not creating new roles)
  services_using_override = {}
}

###############################################################################
# Unified IAM Policy Module
###############################################################################
module "service_policy" {
  source = "../../../modules/iam-policy"

  for_each = var.spoke_iam_policies

  service_name       = each.key
  policy_inline_json = each.value

  # GCP placeholder replacement
  project_id     = data.google_project.current.project_id
  project_number = data.google_project.current.number
}

###############################################################################
# Unified Spoke Role Module
###############################################################################
module "service_role" {
  source = "../../../modules/gcp-spoke-role"

  for_each = local.services_needing_roles

  create = true

  spoke_alias               = var.spoke_alias
  service_name              = each.key
  project_id                = var.project_id
  csoc_service_account_email = each.value.csoc_sa_email
  roles                     = ["roles/viewer"]
  custom_role_id            = ""

  depends_on = [module.service_policy]
}

###############################################################################
# ArgoCD ConfigMap per Spoke
###############################################################################
module "argocd_configmap" {
  source = "../../../modules/configmap"

  create           = var.enable_argocd && var.enable_vpc && var.enable_k8s_cluster
  context          = var.spoke_alias
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace
  outputs_dir      = var.outputs_dir

  pod_identities = merge(
    {
      for k, v in module.service_role : k => {
        role_arn              = "" # Not applicable for GCP
        role_name             = "${var.spoke_alias}-${k}"
        policy_arn            = "" # Not applicable for GCP
        service_name          = k
        policy_source         = "spoke_created"
        service_account_email = lookup(local.services_needing_roles[k], "csoc_sa_email", "")
      }
    },
    {
      for k, v in local.services_using_override : k => {
        role_arn      = "" # Not applicable for GCP
        role_name     = "override"
        policy_arn    = "" # Not applicable for GCP
        service_name  = k
        policy_source = "spoke_override"
      }
    }
  )

  addon_configs = var.csoc_addon_configs

  cluster_info = var.cluster_info

  gitops_context = merge(
    var.csoc_cluster_secret_annotations,
    {
      spoke_alias  = var.spoke_alias
      spoke_region = var.region
    }
  )

  spokes = {}

  depends_on = [module.service_role]
}


