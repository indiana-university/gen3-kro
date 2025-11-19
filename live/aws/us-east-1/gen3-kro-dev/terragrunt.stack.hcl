###############################################################################
# Terragrunt Stack Configuration
# Main configuration for gen3-kro infrastructure deployment
###############################################################################

###############################################################################
# Base Path Configuration
###############################################################################
locals {
  repo_root      = get_repo_root()
  terragrunt_dir = get_terragrunt_dir()

  # Module and unit paths for Terraform sources
  modules_path = "terraform/catalog/modules"
  units_path   = "${get_repo_root()}/terraform/catalog/units"

  ###############################################################################
  # Configuration Loading and Parsing
  ###############################################################################
  secrets_file = "${local.terragrunt_dir}/secrets.yaml"
  config       = yamldecode(file(local.secrets_file))

  csoc_config    = lookup(local.config, "csoc", {})
  paths_config   = lookup(local.config, "paths", {})
  spokes_config  = lookup(local.config, "spokes", [])
  backend_config = lookup(local.config, "backend", {})

  ###############################################################################
  # Provider Configuration
  ###############################################################################
  csoc_provider_config = lookup(local.csoc_config, "provider", {})
  csoc_provider        = lookup(local.csoc_provider_config, "name", "aws")
  csoc_alias           = lookup(local.csoc_config, "alias", "csoc")
  cluster_name         = lookup(local.csoc_config, "cluster_name", "")

  # AWS Configuration
  region  = lookup(local.csoc_provider_config, "region", "us-east-1")
  profile = lookup(local.csoc_provider_config, "profile", "")

  # Azure Configuration
  subscription_id = lookup(local.csoc_provider_config, "subscription_id", "")
  tenant_id       = lookup(local.csoc_provider_config, "tenant_id", "")
  location        = lookup(local.csoc_provider_config, "location", "eastus")

  # GCP Configuration
  project_id       = lookup(local.csoc_provider_config, "project_id", "")
  credentials_file = lookup(local.csoc_provider_config, "credentials_file", "")

  ###############################################################################
  # Backend State Configuration
  ###############################################################################
  state_bucket          = lookup(local.csoc_provider_config, "terraform_state_bucket", "")
  state_locks_table     = lookup(local.csoc_provider_config, "terraform_locks_table", "")
  state_storage_account = lookup(local.csoc_provider_config, "terraform_state_storage_account", "")
  state_container       = lookup(local.csoc_provider_config, "terraform_state_container", "tfstate")

  ###############################################################################
  # VPC/Network Configuration
  ###############################################################################
  vpc_config           = lookup(local.csoc_config, "vpc", {})
  enable_vpc           = lookup(local.vpc_config, "enable_vpc", false)
  vpc_name             = lookup(local.vpc_config, "vpc_name", "")
  vpc_cidr             = lookup(local.vpc_config, "vpc_cidr", "10.0.0.0/16")
  enable_nat_gateway   = lookup(local.vpc_config, "enable_nat_gateway", false)
  single_nat_gateway   = lookup(local.vpc_config, "single_nat_gateway", false)
  public_subnet_tags   = lookup(local.vpc_config, "public_subnet_tags", {})
  private_subnet_tags  = lookup(local.vpc_config, "private_subnet_tags", {})
  availability_zones   = lookup(local.vpc_config, "availability_zones", [])
  private_subnet_cidrs = lookup(local.vpc_config, "private_subnet_cidrs", [])
  public_subnet_cidrs  = lookup(local.vpc_config, "public_subnet_cidrs", [])

  ###############################################################################
  # Kubernetes Cluster Configuration
  ###############################################################################
  k8s_cluster_config                       = lookup(local.csoc_config, "k8s_cluster", {})
  enable_k8s_cluster                       = lookup(local.k8s_cluster_config, "enable_cluster", false)
  cluster_version                          = lookup(local.k8s_cluster_config, "kubernetes_version", "1.33")
  cluster_endpoint_public_access           = lookup(local.k8s_cluster_config, "cluster_endpoint_public_access", false)
  enable_cluster_creator_admin_permissions = lookup(local.k8s_cluster_config, "enable_cluster_creator_admin_permissions", false)
  k8s_cluster_tags                         = lookup(local.k8s_cluster_config, "cluster_tags", {})
  cluster_compute_config                   = lookup(local.k8s_cluster_config, "cluster_compute_config", {})

  ###############################################################################
  # GitOps Configuration
  ###############################################################################
  # CSOC GitOps - for control plane/hub deployments
  csoc_gitops_config         = lookup(local.csoc_config, "gitops", {})
  csoc_gitops_org_name       = lookup(local.csoc_gitops_config, "org_name", "")
  csoc_gitops_repo_name      = lookup(local.csoc_gitops_config, "repo_name", "")
  csoc_gitops_github_url     = lookup(local.csoc_gitops_config, "github_url", "github.com")
  csoc_gitops_branch         = lookup(local.csoc_gitops_config, "branch", "main")
  csoc_gitops_bootstrap_path = lookup(local.csoc_gitops_config, "bootstrap_path", "")

  # Spokes GitOps - for spoke infrastructure deployments
  spokes_gitops_config     = lookup(local.config, "spokes_gitops", {})
  spokes_gitops_org_name   = lookup(local.spokes_gitops_config, "org_name", local.csoc_gitops_org_name)
  spokes_gitops_repo_name  = lookup(local.spokes_gitops_config, "repo_name", local.csoc_gitops_repo_name)
  spokes_gitops_github_url = lookup(local.spokes_gitops_config, "github_url", local.csoc_gitops_github_url)
  spokes_gitops_branch     = lookup(local.spokes_gitops_config, "branch", local.csoc_gitops_branch)
  spokes_gitops_path       = lookup(local.spokes_gitops_config, "path", "argocd/deployments/gen3-spokes")
  spokes_gitops_repo_url   = format("https://%s/%s/%s.git", local.spokes_gitops_github_url, local.spokes_gitops_org_name, local.spokes_gitops_repo_name)

  # Computed GitOps URLs and paths
  csoc_repo_url        = format("https://%s/%s/%s.git", local.csoc_gitops_github_url, local.csoc_gitops_org_name, local.csoc_gitops_repo_name)
  csoc_repo_basepath   = trimsuffix(local.csoc_gitops_bootstrap_path, "/bootstrap")

  # Load separate config sections
  addon_original_configs = lookup(local.csoc_config, "addon_configs", {})
  ack_original_configs   = lookup(local.csoc_config, "ack_configs", {})
  aso_original_configs   = lookup(local.csoc_config, "aso_configs", {})
  gcc_original_configs   = lookup(local.csoc_config, "gcc_configs", {})

  # Compute ArgoCD identity flag first to break circular dependency
  argocd_identity_flag = lookup(lookup(local.addon_original_configs, "argocd", {}), "enable_argocd", false)

  # General addon configs (ArgoCD, External Secrets, etc.) - only enabled ones
  addon_configs = {
    for addon, addon_config in local.addon_original_configs :
    addon => merge(
      {
        # ArgoCD uses hardcoded "argocd" namespace, others use addon name as namespace
        namespace = addon == "argocd" ? "argocd" : addon
        # ArgoCD service accounts are created by Helm chart, others need manual creation
        service_account = addon == "argocd" ? "argocd-server" : "${addon}-sa"
        # Explicitly set enable_identity for all addons
        enable_identity = addon == "argocd" ? false : lookup(addon_config, "enable_identity", false)
      },
      addon_config
    )
    if lookup(addon_config, "enable_identity", false) || (addon == "argocd" && local.argocd_identity_flag)
  }

  # ACK configs (AWS Controllers for Kubernetes) - only enabled ones
  ack_configs = {
    for ack, ack_config in local.ack_original_configs :
    ack => merge(
      {
        namespace       = "${ack}-system"
        service_account = "${ack}-sa"
      },
      ack_config
    )
    if lookup(ack_config, "enable_identity", false)
  }

  # ASO configs (Azure Service Operator) - only enabled ones
  aso_configs = {
    for aso, aso_config in local.aso_original_configs :
    aso => merge(
      {
        namespace       = "${aso}-system"
        service_account = "${aso}-sa"
      },
      aso_config
    )
    if lookup(aso_config, "enable_identity", false)
  }

  # GCC configs (GCP Config Connector) - only enabled ones
  gcc_configs = {
    for gcc, gcc_config in local.gcc_original_configs :
    gcc => merge(
      {
        namespace       = "${gcc}-system"
        service_account = "${gcc}-sa"
      },
      gcc_config
    )
    if lookup(gcc_config, "enable_identity", false)
  }

  # Combined configs for backward compatibility (used by some units that expect all configs together)
  all_configs = merge(
    local.addon_configs,
    local.ack_configs,
    local.aso_configs,
    local.gcc_configs
  )

  # Recalculate outputs_dir from repo root
  # Priority: 1) TG_OUTPUTS_DIR env var (from dev.sh/prod.sh), 2) secrets.yaml, 3) default
  outputs_dir = get_env("TG_OUTPUTS_DIR", "${local.repo_root}/${lookup(local.paths_config, "outputs_dir", "outputs/terraform")}")

  iam_base_path = lookup(local.paths_config, "iam_base_path", "iam")

  iam_provider_path = "${local.iam_base_path}/${local.csoc_provider}"

  ###############################################################################
  # Spoke Configuration
  ###############################################################################
  spokes = [
    for spoke in local.spokes_config :
    spoke if lookup(spoke, "enabled", false)
  ]

  ###############################################################################
  # Tagging Configuration
  ###############################################################################
  base_tags = merge(
    {
      Terraform = "true"
    },
    lookup(local.config, "tags", {}),
    lookup(local.csoc_config, "tags", {})
  )

  ###############################################################################
  # Computed Enablement Flags
  ###############################################################################
  enable_multi_acct  = length(local.spokes) > 0

  ###############################################################################
  # ArgoCD Configuration
  ###############################################################################
  argocd_config_obj    = lookup(local.addon_configs, "argocd", {})
  enable_argocd        = lookup(local.argocd_config_obj, "enable_argocd", false)

  ###############################################################################
  # Spoke Configuration (for ArgoCD gitops metadata)
  ###############################################################################
  spokes_list = [
    for spoke in local.spokes : {
      alias        = spoke.alias
      region       = lookup(spoke, "region", "")
      cluster_name = lookup(spoke, "cluster_name", "${local.cluster_name}-${spoke.alias}")
      repo_url     = lookup(lookup(spoke, "gitops", {}), "repo_url", local.spokes_gitops_repo_url)
      branch       = lookup(lookup(spoke, "gitops", {}), "branch", local.spokes_gitops_branch)
      argo_path    = lookup(lookup(spoke, "gitops", {}), "argo_path", "${local.spokes_gitops_path}/${spoke.alias}")
    }
  ]

  ###############################################################################
  # IAM Policies - CSOC
  # Load IAM policies for CSOC services from repository files
  ###############################################################################
  csoc_iam_policies = {
    for service_name, service_config in local.all_configs :
    service_name => try(
      local.csoc_provider == "aws" ? file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/inline-policy.json") : (
        local.csoc_provider == "azure" ? file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.json") : (
          local.csoc_provider == "gcp" ? yamlencode(yamldecode(file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.yaml"))) : null
        )
      ),
      local.csoc_provider == "aws" ? file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/inline-policy.json") : (
        local.csoc_provider == "azure" ? file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.json") : (
          local.csoc_provider == "gcp" ? yamlencode(yamldecode(file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.yaml"))) : null
        )
      ),
      null
    )
    if lookup(service_config, "enable_identity", false)
  }

  # Track IAM policy sources for CSOC (which folder was used)
  csoc_iam_policy_sources = {
    for service_name, service_config in local.all_configs :
    service_name => (
      # Try csoc-specific path first, then _default, then none
      local.csoc_provider == "aws" ? (
        fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/inline-policy.json") ? "${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/inline-policy.json" : (
          fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/inline-policy.json") ? "${local.iam_provider_path}/_default/${service_name}/inline-policy.json" : "none"
        )
      ) : local.csoc_provider == "azure" ? (
        fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.json") ? "${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.json" : (
          fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.json") ? "${local.iam_provider_path}/_default/${service_name}/role-definition.json" : "none"
        )
      ) : local.csoc_provider == "gcp" ? (
        fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.yaml") ? "${local.iam_provider_path}/${local.csoc_alias}/csoc/${service_name}/role-definition.yaml" : (
          fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.yaml") ? "${local.iam_provider_path}/_default/${service_name}/role-definition.yaml" : "none"
        )
      ) : "none"
    )
    if lookup(service_config, "enable_identity", false)
  }

  ###############################################################################
  # IAM Policies - Spoke
  # Load IAM policies for spoke services from repository files
  ###############################################################################
  spoke_iam_policies = {
    for spoke in local.spokes :
    spoke.alias => {
      # Merge all spoke config types for backward compatibility
      for service_name, service_config in merge(
        lookup(spoke, "addon_configs", {}),
        lookup(spoke, "ack_configs", {}),
        lookup(spoke, "aso_configs", {}),
        lookup(spoke, "gcc_configs", {})
      ) :
      service_name => try(
        local.csoc_provider == "aws" ? file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/inline-policy.json") : (
          local.csoc_provider == "azure" ? file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.json") : (
            local.csoc_provider == "gcp" ? yamlencode(yamldecode(file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.yaml"))) : null
          )
        ),
        local.csoc_provider == "aws" ? file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/inline-policy.json") : (
          local.csoc_provider == "azure" ? file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.json") : (
            local.csoc_provider == "gcp" ? yamlencode(yamldecode(file("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.yaml"))) : null
          )
        ),
        null
      )
      if lookup(service_config, "enable_identity", false)
    }
  }

  # Track IAM policy sources for Spokes (which folder was used)
  spoke_iam_policy_sources = {
    for spoke in local.spokes :
    spoke.alias => {
      # Merge all spoke config types for backward compatibility
      for service_name, service_config in merge(
        lookup(spoke, "addon_configs", {}),
        lookup(spoke, "ack_configs", {}),
        lookup(spoke, "aso_configs", {}),
        lookup(spoke, "gcc_configs", {})
      ) :
      service_name => (
        # Try spoke-specific path first, then _default, then none
        local.csoc_provider == "aws" ? (
          fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/inline-policy.json") ? "${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/inline-policy.json" : (
            fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/inline-policy.json") ? "${local.iam_provider_path}/_default/${service_name}/inline-policy.json" : "none"
          )
        ) : local.csoc_provider == "azure" ? (
          fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.json") ? "${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.json" : (
            fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.json") ? "${local.iam_provider_path}/_default/${service_name}/role-definition.json" : "none"
          )
        ) : local.csoc_provider == "gcp" ? (
          fileexists("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.yaml") ? "${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/${service_name}/role-definition.yaml" : (
            fileexists("${local.repo_root}/${local.iam_provider_path}/_default/${service_name}/role-definition.yaml") ? "${local.iam_provider_path}/_default/${service_name}/role-definition.yaml" : "none"
          )
        ) : "none"
      )
      if lookup(service_config, "enable_identity", false)
    }
  }
}

###############################################################################
# VPC Unit
# VPC infrastructure for the CSOC (hub) cluster
###############################################################################
unit "vpc" {
  source = "${local.units_path}/vpc"
  path   = "vpc"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    cluster_name  = local.cluster_name

    region  = local.region
    profile = local.profile

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container
    csoc_alias            = local.csoc_alias

    # VPC configuration
    enable_vpc           = local.enable_vpc
    vpc_name             = local.vpc_name
    vpc_cidr             = local.vpc_cidr
    enable_nat_gateway   = local.enable_nat_gateway
    single_nat_gateway   = local.single_nat_gateway
    public_subnet_tags   = local.public_subnet_tags
    private_subnet_tags  = local.private_subnet_tags
    availability_zones   = local.availability_zones
    private_subnet_cidrs = local.private_subnet_cidrs
    public_subnet_cidrs  = local.public_subnet_cidrs
  }
}

###############################################################################
# k8s Cluster Unit
# EKS cluster, Pod Identities, and Cross-Account Policies
###############################################################################
unit "k8s_cluster" {
  source = "${local.units_path}/k8s-cluster"
  path   = "k8s-cluster"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    cluster_name  = local.cluster_name
    csoc_alias    = local.csoc_alias

    region  = local.region
    profile = local.profile

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container

    # Kubernetes cluster configuration (cloud-agnostic)
    enable_k8s_cluster                       = local.enable_k8s_cluster
    cluster_version                          = local.cluster_version
    cluster_endpoint_public_access           = local.cluster_endpoint_public_access
    enable_cluster_creator_admin_permissions = local.enable_cluster_creator_admin_permissions
    cluster_compute_config                   = local.cluster_compute_config
  }
}

###############################################################################
# IAM Config Unit
# Spoke cluster IAM roles and configurations
###############################################################################
unit "iam_config" {
  source = "${local.units_path}/iam-config"
  path   = "iam-config"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    csoc_alias    = local.csoc_alias

    region  = local.region
    profile = local.profile

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container

    spokes_config = local.spokes

    # IAM policies (loaded from repository files)
    csoc_iam_policies  = local.csoc_iam_policies
    spoke_iam_policies = local.spoke_iam_policies

    # IAM policy sources (track which folder was used)
    csoc_iam_policy_sources  = local.csoc_iam_policy_sources
    spoke_iam_policy_sources = local.spoke_iam_policy_sources

    # Controller configurations - unified map of all controllers
    all_configs = local.all_configs

    # Cluster existence flag
    enable_k8s_cluster = local.enable_k8s_cluster
    cluster_name       = local.cluster_name

    # Spokes configuration with cluster secret annotations
    spokes = {
      for spoke in local.spokes :
      spoke.alias => {
        enabled       = lookup(spoke, "enabled", false)
        region        = lookup(spoke, "region", local.region)
        cluster_name  = lookup(spoke, "cluster_name", "${local.cluster_name}-${spoke.alias}")
        # Merge all config types for each spoke
        addon_configs = merge(
          lookup(spoke, "addon_configs", {}),
          lookup(spoke, "ack_configs", {}),
          lookup(spoke, "aso_configs", {}),
          lookup(spoke, "gcc_configs", {})
        )
        cluster_secret_annotations = merge(
          {
            # Repository Configuration - uses spokes_gitops as default
            repo_url      = lookup(lookup(spoke, "gitops", {}), "repo_url", local.spokes_gitops_repo_url)
            repo_revision = lookup(lookup(spoke, "gitops", {}), "branch", local.spokes_gitops_branch)
            argo_path     = lookup(lookup(spoke, "gitops", {}), "argo_path", "${local.spokes_gitops_path}/${spoke.alias}")

            # Cluster Information
            spoke_alias        = spoke.alias
            spoke_region       = lookup(spoke, "region", local.region)
            spoke_cluster_name = lookup(spoke, "cluster_name", "${local.cluster_name}-${spoke.alias}")
          },
          lookup(spoke, "cluster_secret_annotations", {})
        )
      }
    }
  }
}

###############################################################################
# ArgoCD Core Unit
# ArgoCD deployment itself
###############################################################################
unit "argocd_core" {
  source = "${local.units_path}/k8s-argocd-core"
  path   = "k8s-argocd-core"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    cluster_name  = local.cluster_name
    csoc_alias    = local.csoc_alias

    region = local.region

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    azure_client_id     = lookup(local.csoc_provider_config, "client_id", "")
    azure_client_secret = lookup(local.csoc_provider_config, "client_secret", "")

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container

    enable_argocd = local.enable_argocd
    outputs_dir   = local.outputs_dir

    # Computed GitOps values (computed in stack, passed to unit)
    csoc_repo_url             = local.csoc_repo_url
    csoc_repo_basepath        = local.csoc_repo_basepath
    csoc_gitops_branch        = local.csoc_gitops_branch
    csoc_gitops_bootstrap_path = local.csoc_gitops_bootstrap_path
  }
}

###############################################################################
# K8s Controller Requirements Unit
# Unified controller namespaces, service accounts, and configmaps
# Supports: Addon, ACK, ASO, GCC controllers (cloud-agnostic)
###############################################################################
unit "k8s_controller_req" {
  source = "${local.units_path}/k8s-controller-req"
  path   = "k8s-controller-req"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    csoc_alias    = local.csoc_alias

    region = local.region

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    azure_client_id     = lookup(local.csoc_provider_config, "client_id", "")
    azure_client_secret = lookup(local.csoc_provider_config, "client_secret", "")

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container

    enable_argocd = local.enable_argocd

    # Unified controller configurations (all types)
    all_configs = local.all_configs

    # Individual controller type configs (for component labeling)
    ack_configs = local.ack_configs
    aso_configs = local.aso_configs
    gcc_configs = local.gcc_configs

    spokes = {
      for spoke in local.spokes :
      spoke.alias => spoke
    }
  }
}

###############################################################################
# K8s Spoke Requirements Unit
# Spoke namespaces and spoke charter configmaps
###############################################################################
unit "k8s_spoke_req" {
  source = "${local.units_path}/k8s-spoke-req"
  path   = "k8s-spoke-req"

  values = {
    modules_path = local.modules_path

    csoc_provider = local.csoc_provider
    tags          = local.base_tags
    csoc_alias    = local.csoc_alias

    region = local.region

    subscription_id = local.subscription_id
    tenant_id       = local.tenant_id
    location        = local.location

    azure_client_id     = lookup(local.csoc_provider_config, "client_id", "")
    azure_client_secret = lookup(local.csoc_provider_config, "client_secret", "")

    project_id       = local.project_id
    credentials_file = local.credentials_file

    state_bucket          = local.state_bucket
    state_locks_table     = local.state_locks_table
    state_storage_account = local.state_storage_account
    state_container       = local.state_container

    enable_argocd = local.enable_argocd

    spokes = {
      for spoke in local.spokes :
      spoke.alias => spoke
    }
  }
}

###############################################################################
# End of File
###############################################################################
