locals {
  repo_root    = get_repo_root()
  modules_path = "terraform/catalog/modules"
  units_path   = "${local.repo_root}/terraform/catalog/units"
  config       = jsondecode(file("${local.repo_root}/config/shared.auto.tfvars.json"))

  region          = lookup(local.config, "region", "us-east-1")
  profile         = lookup(local.config, "aws_profile", "")
  csoc_account_id = lookup(local.config, "csoc_account_id", "")
  csoc_alias      = lookup(local.config, "csoc_alias", "csoc")
  cluster_name    = "${local.csoc_alias}-csoc-cluster"
  state_bucket    = lookup(local.config, "backend_bucket", "")
  backend_region  = lookup(local.config, "backend_region", local.region)
  tags            = merge({ Terraform = "true", ManagedBy = "terragrunt", Stack = "csoc-cluster-core" }, lookup(local.config, "tags", {}))

  common = {
    modules_path    = local.modules_path
    profile         = local.profile
    region          = local.region
    state_bucket    = local.state_bucket
    backend_region  = local.backend_region
    csoc_alias      = local.csoc_alias
    csoc_account_id = local.csoc_account_id
    cluster_name    = local.cluster_name
    environment     = lookup(local.config, "environment", "control-plane")
    tags            = local.tags
  }
}

unit "aws_csoc_cluster" {
  source = "${local.units_path}/aws-csoc-cluster"
  path   = "aws-csoc-cluster"

  values = merge(local.common, {
    state_key                                = "csoc/aws-csoc-cluster/terraform.tfstate"
    operator_state_key                       = "prereq/aws-csoc-operator-iam/terraform.tfstate"
    vpc_cidr                                 = lookup(local.config, "vpc_cidr", "10.0.0.0/16")
    availability_zones                       = lookup(local.config, "availability_zones", [])
    private_subnet_cidrs                     = lookup(local.config, "private_subnet_cidrs", [])
    public_subnet_cidrs                      = lookup(local.config, "public_subnet_cidrs", [])
    public_subnet_tags                       = lookup(local.config, "public_subnet_tags", {})
    private_subnet_tags                      = lookup(local.config, "private_subnet_tags", {})
    enable_nat_gateway                       = lookup(local.config, "enable_nat_gateway", true)
    single_nat_gateway                       = lookup(local.config, "single_nat_gateway", true)
    kubernetes_version                       = lookup(local.config, "kubernetes_version", "1.35")
    cluster_endpoint_public_access           = lookup(local.config, "cluster_endpoint_public_access", true)
    enable_cluster_creator_admin_permissions = false
    cluster_compute_config                   = lookup(local.config, "cluster_compute_config", { enabled = true, node_pools = ["general-purpose", "system"] })
  })
}

unit "aws_csoc_controller_iam" {
  source = "${local.units_path}/aws-csoc-controller-iam"
  path   = "aws-csoc-controller-iam"

  values = merge(local.common, {
    state_key                        = "csoc/aws-csoc-controller-iam/terraform.tfstate"
    cluster_unit_path                = "../aws-csoc-cluster"
    argocd_namespace                 = lookup(local.config, "argocd_namespace", "argocd")
    ack_namespace                    = lookup(local.config, "ack_namespace", "ack")
    external_secrets_namespace       = lookup(local.config, "external_secrets_namespace", "external-secrets")
    external_secrets_service_account = lookup(local.config, "external_secrets_service_account", "external-secrets-sa")
    addons                           = lookup(local.config, "addons", {})
    ack_management_type              = lookup(local.config, "ack_management_type", "self_managed")
    kro_management_type              = lookup(local.config, "kro_management_type", "self_managed")
    argocd_management_type           = lookup(local.config, "argocd_management_type", "self_managed")
    enable_ack_capability            = lookup(local.config, "enable_ack_capability", false)
    enable_kro_capability            = lookup(local.config, "enable_kro_capability", false)
    enable_argocd_capability         = lookup(local.config, "enable_argocd_capability", false)
    enable_ack_self_managed          = lookup(local.config, "enable_ack_self_managed", false)
    enable_argocd_self_managed       = lookup(local.config, "enable_argocd_self_managed", false)
  })
}

unit "gitops_argocd_install" {
  source = "${local.units_path}/gitops-argocd-install"
  path   = "gitops-argocd-install"

  values = merge(local.common, {
    state_key                  = "csoc/gitops-argocd-install/terraform.tfstate"
    cluster_unit_path          = "../aws-csoc-cluster"
    controller_unit_path       = "../aws-csoc-controller-iam"
    enabled                    = lookup(local.config, "argocd_bootstrap_enabled", true) || lookup(local.config, "enable_argocd_self_managed", false) || lookup(local.config, "enable_argocd_capability", false)
    argocd_namespace           = lookup(local.config, "argocd_namespace", "argocd")
    argocd_chart_version       = lookup(local.config, "argocd_chart_version", "7.0.0")
    argocd_chart_repository    = lookup(local.config, "argocd_chart_repository", "https://argoproj.github.io/argo-helm")
    argocd_values              = lookup(local.config, "argocd_values", {})
    enable_argocd_self_managed = lookup(local.config, "enable_argocd_self_managed", false)
    enable_argocd_capability   = lookup(local.config, "enable_argocd_capability", false)
    argocd_bootstrap_enabled   = lookup(local.config, "argocd_bootstrap_enabled", true)
  })
}
