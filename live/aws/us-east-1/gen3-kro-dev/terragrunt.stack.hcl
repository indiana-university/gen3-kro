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

  catalog_path = "${get_repo_root()}/terraform/catalog"
  units_path   = "${get_repo_root()}/terraform/units"

###############################################################################
# Configuration Loading and Parsing
###############################################################################
  secrets_file = "${local.terragrunt_dir}/secrets.yaml"
  config       = yamldecode(file(local.secrets_file))

  csoc_config    = lookup(local.config, "csoc", {})
  paths_config   = lookup(local.config, "paths", {})
  rgds_config    = lookup(local.config, "rgds", {})
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
  state_bucket          = lookup(local.csoc_provider_config, "terraform_state_bucket", lookup(local.backend_config, "terraform_state_bucket", ""))
  state_locks_table     = lookup(local.backend_config, "terraform_locks_table", "")
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
  vpc_tags             = lookup(local.vpc_config, "vpc_tags", {})
  public_subnet_tags   = lookup(local.vpc_config, "public_subnet_tags", {})
  private_subnet_tags  = lookup(local.vpc_config, "private_subnet_tags", {})
  existing_vpc_id      = lookup(local.vpc_config, "existing_vpc_id", "")
  existing_subnet_ids  = lookup(local.vpc_config, "existing_subnet_ids", [])
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
  csoc_gitops_config         = lookup(local.csoc_config, "gitops", {})
  csoc_gitops_org_name       = lookup(local.csoc_gitops_config, "org_name", "")
  csoc_gitops_repo_name      = lookup(local.csoc_gitops_config, "repo_name", "")
  csoc_gitops_github_url     = lookup(local.csoc_gitops_config, "github_url", "github.com")
  csoc_gitops_branch         = lookup(local.csoc_gitops_config, "branch", "main")
  csoc_gitops_bootstrap_path = lookup(local.csoc_gitops_config, "bootstrap_path", "")

###############################################################################
# Addon and IAM Configuration
###############################################################################
  addon_configs = lookup(local.csoc_config, "addon_configs", {})

  outputs_dir            = lookup(local.paths_config, "outputs_dir", "../../../../../../../../../../outputs")
  terraform_state_bucket = local.state_bucket
  terraform_locks_table  = lookup(local.csoc_provider_config, "terraform_locks_table", "")

  iam_base_path = lookup(local.paths_config, "iam_base_path", "iam")

  iam_provider_path = "${local.iam_base_path}/${local.csoc_provider}"

###############################################################################
# Resource Graph Definitions (RGD) GitOps Configuration
###############################################################################
  rgds_gitops_config      = lookup(local.rgds_config, "gitops", {})
  rgds_gitops_org_name    = lookup(local.rgds_gitops_config, "org_name", "")
  rgds_gitops_repo_name   = lookup(local.rgds_gitops_config, "repo_name", "")
  rgds_gitops_github_url  = lookup(local.rgds_gitops_config, "github_url", "github.com")
  rgds_gitops_branch      = lookup(local.rgds_gitops_config, "branch", "main")
  rgds_gitops_argocd_path = lookup(local.rgds_gitops_config, "argocd_path", "")

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
      Terraform   = "true"
      Environment = local.csoc_alias
    },
    lookup(local.config, "tags", {}),
    lookup(local.csoc_config, "tags", {})
  )

###############################################################################
# Computed Enablement Flags
###############################################################################
  enable_multi_acct  = length(local.spokes) > 0
  enable_spoke_roles = local.enable_multi_acct && length(local.addon_configs) > 0

###############################################################################
# ArgoCD Configuration
###############################################################################
  argocd_config_obj    = lookup(local.addon_configs, "argocd", {})
  enable_argocd        = lookup(local.argocd_config_obj, "enable_identity", false)
  argocd_namespace     = lookup(local.argocd_config_obj, "namespace", "argocd")
  argocd_chart_version = lookup(local.argocd_config_obj, "argocd_chart_version", "8.6.0")

###############################################################################
# Constructed URLs and Paths
###############################################################################
  csoc_repo_url = format("https://%s/%s/%s.git", local.csoc_gitops_github_url, local.csoc_gitops_org_name, local.csoc_gitops_repo_name)

###############################################################################
# ArgoCD Helm Chart Configuration
###############################################################################
  argocd_config = {
    namespace     = local.argocd_namespace
    chart         = "argo-cd"
    repository    = "https://argoproj.github.io/argo-helm"
    chart_version = local.argocd_chart_version
  }

###############################################################################
# ArgoCD GitOps Metadata
# Cross-account and multi-cluster GitOps configuration
###############################################################################
  argocd_gitops = {
    csoc = {
      alias        = local.csoc_alias
      region       = local.region
      cluster_name = local.cluster_name
      repo_url     = local.csoc_repo_url
      branch       = local.csoc_gitops_branch
    }
    spokes = [
      for spoke in local.spokes : {
        alias        = spoke.alias
        region       = lookup(spoke, "region", "")
        cluster_name = lookup(spoke, "cluster_name", "${local.cluster_name}-${spoke.alias}")
        repo_url     = lookup(lookup(spoke, "gitops", {}), "repo_url", local.csoc_repo_url)
        branch       = lookup(lookup(spoke, "gitops", {}), "branch", local.csoc_gitops_branch)
        argo_path    = lookup(lookup(spoke, "gitops", {}), "argo_path", "argocd/spokes")
      }
    ]
    rgds = {
      org_name    = local.rgds_gitops_org_name
      repo_name   = local.rgds_gitops_repo_name
      github_url  = local.rgds_gitops_github_url
      branch      = local.rgds_gitops_branch
      argocd_path = local.rgds_gitops_argocd_path
      repo_url    = local.rgds_gitops_org_name != "" ? format("https://%s/%s/%s.git", local.rgds_gitops_github_url, local.rgds_gitops_org_name, local.rgds_gitops_repo_name) : ""
    }
  }

###############################################################################
# ArgoCD Cluster Configuration
# Cluster secret and metadata for ArgoCD registration
###############################################################################
  csoc_repo_basepath   = trimsuffix(local.csoc_gitops_bootstrap_path, "/bootstrap")           # -> "argocd"
  addons_repo_basepath = "${trimsuffix(local.csoc_gitops_bootstrap_path, "/bootstrap")}/csoc" # -> "argocd/csoc"

  argocd_cluster = {
    cluster_name     = local.cluster_name
    secret_namespace = local.argocd_namespace
    # Addons key is used by argocd module for labels
    addons = {
      # Cluster Categorization
      fleet_member = "control-plane"
      environment  = lookup(local.config, "environment", lookup(lookup(local.config, "tags", {}), "Environment", local.csoc_alias))
      tenant       = lookup(local.config, "tenant", local.csoc_alias) # tenant=csoc_alias for csoc
    }
    metadata = {
      annotations = merge(
        {
          # Repository Configuration (static)
          csoc_repo_url        = local.csoc_repo_url
          csoc_repo_revision   = local.csoc_gitops_branch
          csoc_repo_basepath   = local.csoc_repo_basepath
          addons_repo_url      = local.csoc_repo_url
          addons_repo_revision = local.csoc_gitops_branch
          addons_repo_basepath = local.addons_repo_basepath
          rgds_repo_url        = local.argocd_gitops.rgds.repo_url
          rgds_path            = local.rgds_gitops_argocd_path
          branch               = local.csoc_gitops_branch
          bootstrap_path       = local.csoc_gitops_bootstrap_path

          # Hub/Csoc ApplicationSet references (for ArgoCD ApplicationSet)
          hub_repo_url      = local.csoc_repo_url
          hub_repo_revision = local.csoc_gitops_branch
          hub_repo_basepath = "argocd"

          # Cluster Information (static)
          csoc_cluster_name = local.cluster_name
          csoc_alias        = local.csoc_alias
          csoc_region       = local.region
        },
        # Addon namespace annotations
        { for name, cfg in local.addon_configs :
          "${replace(name, "_", "-")}_namespace" => lookup(cfg, "namespace", name)
        },
        { for name, cfg in local.addon_configs :
          "${replace(name, "_", "-")}_service_account" => lookup(cfg, "service_account", name)
        }
      )
    }
    gitops_context = local.argocd_gitops
  }

###############################################################################
# AWS EKS Token Configuration
# AWS CLI arguments for EKS authentication
###############################################################################
  csoc_exec_args_base = [
    "eks",
    "get-token",
    "--cluster-name",
    local.cluster_name,
    "--region",
    local.region
  ]

  csoc_exec_args = local.profile != "" ? concat(local.csoc_exec_args_base, ["--profile", local.profile]) : local.csoc_exec_args_base

###############################################################################
# IAM Policies - CSOC
# Load IAM policies for CSOC services from repository files
###############################################################################
  csoc_iam_policies = {
    for service_name, service_config in local.addon_configs :
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

###############################################################################
# IAM Policies - Spoke
# Load IAM policies for spoke services from repository files
###############################################################################
  spoke_iam_policies = {
    for spoke in local.spokes :
    spoke.alias => {
      for service_name, service_config in lookup(spoke, "addon_configs", {}) :
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

###############################################################################
# Spoke ARN Inputs
# Load spoke role ARNs from JSON files for cross-account access
###############################################################################
  spoke_arn_inputs = {
    for spoke in local.spokes : spoke.alias => {
      for controller_name in keys(local.addon_configs) : controller_name =>
      try(
        jsondecode(file("${local.repo_root}/${local.iam_provider_path}/${local.csoc_alias}/${spoke.alias}/addons/${controller_name}.json")),
        null
      )
    }
  }
}

###############################################################################
# Terragrunt Unit Definitions
###############################################################################

###############################################################################
# CSOC (Control Plane) Unit
# Hub cluster infrastructure and ArgoCD deployment
###############################################################################
unit "csoc" {
  source = "${local.units_path}//csoc"
  path   = "units/csoc"

  values = {
    catalog_path = local.catalog_path
    units_path   = local.units_path

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

    # VPC configuration
    enable_vpc          = local.enable_vpc
    vpc_name            = local.vpc_name
    vpc_cidr            = local.vpc_cidr
    enable_nat_gateway  = local.enable_nat_gateway
    single_nat_gateway  = local.single_nat_gateway
    vpc_tags            = local.vpc_tags
    public_subnet_tags  = local.public_subnet_tags
    private_subnet_tags = local.private_subnet_tags
    existing_vpc_id     = local.existing_vpc_id
    existing_subnet_ids = local.existing_subnet_ids
    # Explicit subnet configuration provided via module variables
    availability_zones   = local.availability_zones
    private_subnet_cidrs = local.private_subnet_cidrs
    public_subnet_cidrs  = local.public_subnet_cidrs

    # Kubernetes cluster configuration (cloud-agnostic)
    enable_k8s_cluster                       = local.enable_k8s_cluster
    cluster_version                          = local.cluster_version
    cluster_endpoint_public_access           = local.cluster_endpoint_public_access
    enable_cluster_creator_admin_permissions = local.enable_cluster_creator_admin_permissions
    k8s_cluster_tags                         = local.k8s_cluster_tags
    cluster_compute_config                   = local.cluster_compute_config

    # Addon configurations (structured from config.yaml)
    addon_configs = local.addon_configs

    # Enable flags (computed)
    enable_multi_acct = local.enable_multi_acct

    # Spoke ARN inputs (loaded from JSON files or empty)
    spoke_arn_inputs = local.spoke_arn_inputs

    # IAM policies (loaded from repository files)
    csoc_iam_policies = local.csoc_iam_policies

    # ArgoCD configuration
    enable_argocd      = local.enable_argocd
    argocd_config      = local.argocd_config
    argocd_install     = true
    argocd_cluster     = local.argocd_cluster
    argocd_outputs_dir = local.outputs_dir
    argocd_namespace   = local.argocd_namespace
  }
}

###############################################################################
# Spokes Unit
# Spoke cluster IAM roles and configurations
###############################################################################
unit "spokes" {
  source = "${local.units_path}//spokes"
  path   = "units/spokes"

  values = {
    # Path configuration
    catalog_path = local.catalog_path
    units_path   = local.units_path

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

    spokes_config = local.spokes

    csoc_path = "../csoc"

    enable_vpc           = local.enable_vpc
    vpc_name             = local.vpc_name
    vpc_cidr             = local.vpc_cidr
    enable_nat_gateway   = local.enable_nat_gateway
    single_nat_gateway   = local.single_nat_gateway
    vpc_tags             = local.vpc_tags
    public_subnet_tags   = local.public_subnet_tags
    private_subnet_tags  = local.private_subnet_tags
    existing_vpc_id      = local.existing_vpc_id
    existing_subnet_ids  = local.existing_subnet_ids
    availability_zones   = local.availability_zones
    private_subnet_cidrs = local.private_subnet_cidrs
    public_subnet_cidrs  = local.public_subnet_cidrs

    # Kubernetes cluster configuration (cloud-agnostic)
    enable_k8s_cluster                       = local.enable_k8s_cluster
    cluster_version                          = local.cluster_version
    cluster_endpoint_public_access           = local.cluster_endpoint_public_access
    enable_cluster_creator_admin_permissions = local.enable_cluster_creator_admin_permissions
    k8s_cluster_tags                         = local.k8s_cluster_tags
    cluster_compute_config                   = local.cluster_compute_config

    # Addon configurations (csoc addons for reference)
    addon_configs = local.addon_configs

    # ArgoCD namespace
    argocd_namespace = local.argocd_namespace

    # Enable flags (computed)
    enable_multi_acct = local.enable_multi_acct

    # Spoke ARN inputs (loaded from JSON files or empty)
    spoke_arn_inputs = local.spoke_arn_inputs

    # IAM policies (loaded from repository files)
    spoke_iam_policies = local.spoke_iam_policies
  }
}

###############################################################################
# End of File
###############################################################################
