include {
  path = find_in_parent_folders("backend.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform//combinations/hub"
}

locals {
  ###################################################################################################################################################
  # DATA IMPORT SECTION - Imports variables from config.yaml
  ##################################################################################################################################################
  repo_root = get_repo_root()
  config    = yamldecode(file("${get_terragrunt_dir()}/config.yaml"))

  # Direct imports from config.yaml structure
  hub_config    = local.config.hub
  paths_config  = lookup(local.config, "paths", {})
  rgds_config   = lookup(local.config, "rgds", {})
  spokes_config = lookup(local.config, "spokes", [])

  ###################################################################################################################################################
  # FLATTENING SECTION - Takes nested variables and flattens them into individual names
  ###################################################################################################################################################

  # Base configuration
  cluster_name = lookup(lookup(local.hub_config, "vpc", {}), "cluster_name", lookup(local.hub_config, "cluster_name", ""))
  aws_region   = local.hub_config.aws_region
  aws_profile  = local.hub_config.aws_profile
  hub_alias    = local.hub_config.alias

  # VPC configuration from hub.vpc
  vpc_config                = lookup(local.hub_config, "vpc", {})
  enable_vpc                = lookup(local.vpc_config, "enable_vpc", false)
  vpc_name                  = lookup(local.vpc_config, "vpc_name", "")
  vpc_cidr                  = lookup(local.vpc_config, "vpc_cidr", "10.0.0.0/16")
  enable_nat_gateway        = lookup(local.vpc_config, "enable_nat_gateway", false)
  single_nat_gateway        = lookup(local.vpc_config, "single_nat_gateway", false)
  existing_vpc_id           = lookup(local.vpc_config, "existing_vpc_id", "")
  existing_subnet_ids       = lookup(local.vpc_config, "existing_subnet_ids", [])
  # Explicit subnet configuration provided via module variables
  availability_zones        = lookup(local.vpc_config, "availability_zones", [])
  private_subnet_cidrs      = lookup(local.vpc_config, "private_subnet_cidrs", [])
  public_subnet_cidrs       = lookup(local.vpc_config, "public_subnet_cidrs", [])

  # EKS configuration from hub.eks
  eks_config                               = lookup(local.hub_config, "eks", {})
  enable_eks_cluster                       = lookup(local.eks_config, "enable_eks_cluster", false)
  cluster_version                          = lookup(local.eks_config, "kubernetes_version", "1.31")
  cluster_endpoint_public_access           = lookup(local.eks_config, "cluster_endpoint_public_access", false)
  enable_cluster_creator_admin_permissions = lookup(local.eks_config, "enable_cluster_creator_admin_permissions", false)
  cluster_compute_config                   = lookup(local.eks_config, "cluster_compute_config", {})

  # Gitops configuration from hub.gitops
  gitops_config         = lookup(local.hub_config, "gitops", {})
  gitops_org_name       = lookup(local.gitops_config, "org_name", "")
  gitops_repo_name      = lookup(local.gitops_config, "repo_name", "")
  gitops_github_url     = lookup(local.gitops_config, "github_url", "github.com")
  gitops_branch         = lookup(local.gitops_config, "branch", "main")
  gitops_bootstrap_path = lookup(local.gitops_config, "bootstrap_path", "")

  # IAM Gitops configuration from hub.iam_gitops
  iam_gitops_config           = lookup(local.hub_config, "iam_gitops", {})
  iam_gitops_org_name         = lookup(local.iam_gitops_config, "org_name", "")
  iam_gitops_repo_name        = lookup(local.iam_gitops_config, "repo_name", "")
  iam_gitops_github_url       = lookup(local.iam_gitops_config, "github_url", "github.com")
  iam_gitops_branch           = lookup(local.iam_gitops_config, "branch", "main")
  iam_gitops_policy_base_path = lookup(local.iam_gitops_config, "policy_base_path", "")

  # Addon configurations from config.yaml only
  # All addon configs are now sourced from config.yaml hub.addon_configs
  # No merging with disabled-addons.yaml since that file has been removed
  addon_configs = lookup(local.hub_config, "addon_configs", {})

  # ACK configurations from hub.ack_configs
  hub_ack_configs = lookup(local.hub_config, "ack_configs", {})

  # Paths configuration
  outputs_dir            = lookup(local.paths_config, "outputs_dir", "./outputs")
  terraform_state_bucket = lookup(local.paths_config, "terraform_state_bucket", "")
  terraform_locks_table  = lookup(local.paths_config, "terraform_locks_table", "")
  iam_base_path          = local.iam_gitops_policy_base_path != "" ? local.iam_gitops_policy_base_path : lookup(local.paths_config, "iam_base_path", "iam")

  # RGDs configuration
  rgds_gitops_config      = lookup(local.rgds_config, "gitops", {})
  rgds_gitops_org_name    = lookup(local.rgds_gitops_config, "org_name", "")
  rgds_gitops_repo_name   = lookup(local.rgds_gitops_config, "repo_name", "")
  rgds_gitops_github_url  = lookup(local.rgds_gitops_config, "github_url", "github.com")
  rgds_gitops_branch      = lookup(local.rgds_gitops_config, "branch", "main")
  rgds_gitops_argocd_path = lookup(local.rgds_gitops_config, "argocd_path", "")

  ###################################################################################################################################################
  # DERIVED VALUES SECTION - All other variables reference flattened names
  ###################################################################################################################################################

  # Filtered spokes (only enabled ones)
  spokes = [
    for spoke in local.spokes_config :
    spoke if lookup(spoke, "enabled", false)
  ]

  # Base tags
  base_tags = merge(
    {
      Terraform   = "true"
      Environment = local.hub_alias
    },
    lookup(local.config, "tags", {}),
    lookup(local.hub_config, "tags", {})
  )

  # Computed enablement flags
  enable_ack         = length(local.hub_ack_configs) > 0
  enable_multi_acct  = length(local.spokes) > 0
  enable_ack_spoke_roles = local.enable_multi_acct && local.enable_ack

  # ArgoCD enablement from addon_configs
  argocd_config_obj  = lookup(local.addon_configs, "argocd", {})
  enable_argocd      = lookup(local.argocd_config_obj, "enable_pod_identity", false)
  argocd_namespace   = lookup(local.argocd_config_obj, "namespace", "argocd")
  argocd_chart_version = lookup(local.argocd_config_obj, "argocd_chart_version", "8.6.0")

  # Constructed URLs and paths
  hub_repo_url = format("https://%s/%s/%s.git", local.gitops_github_url, local.gitops_org_name, local.gitops_repo_name)

  # IAM Git URL construction (using same repo as hub unless iam_gitops is configured)
  iam_repo_url_base = local.iam_gitops_org_name != "" ? format("https://%s/%s/%s.git", local.iam_gitops_github_url, local.iam_gitops_org_name, local.iam_gitops_repo_name) : local.hub_repo_url
  iam_git_url       = format("git::%s", local.iam_repo_url_base)
  iam_git_branch    = local.iam_gitops_branch != "" ? local.iam_gitops_branch : local.gitops_branch

  # IAM raw file URL for HTTP fetching (GitHub raw content URL)
  # Format: https://raw.githubusercontent.com/{org}/{repo}/{branch}/{path}
  iam_raw_base_url  = local.iam_gitops_org_name != "" ? format("https://raw.githubusercontent.com/%s/%s/%s", local.iam_gitops_org_name, local.iam_gitops_repo_name, local.iam_git_branch) : ""

  # ArgoCD configuration objects
  argocd_config = {
    namespace     = local.argocd_namespace
    chart         = "argo-cd"
    repository    = "https://argoproj.github.io/argo-helm"
    chart_version = local.argocd_chart_version
  }

  # ArgoCD GitOps metadata for cross-account access
  argocd_gitops = {
    hub = {
      alias        = local.hub_alias
      region       = local.aws_region
      cluster_name = local.cluster_name
      repo_url     = local.hub_repo_url
      branch       = local.gitops_branch
    }
    spokes = [
      for spoke in local.spokes : {
        alias        = spoke.alias
        region       = spoke.region
        cluster_name = lookup(spoke, "cluster_name", "${local.cluster_name}-${spoke.alias}")
        repo_url     = lookup(lookup(spoke, "gitops", {}), "repo_url", local.hub_repo_url)
        branch       = lookup(lookup(spoke, "gitops", {}), "branch", local.gitops_branch)
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

  # Computed paths for ArgoCD annotations
  hub_repo_basepath     = trimsuffix(local.gitops_bootstrap_path, "/bootstrap")  # -> "argocd"
  addons_repo_basepath  = "${trimsuffix(local.gitops_bootstrap_path, "/bootstrap")}/hub"  # -> "argocd/hub"

  argocd_cluster = {
    cluster_name     = local.cluster_name
    secret_namespace = local.argocd_namespace
    # Addons key is used by argocd module for labels (not metadata.labels)
    # NOTE: enable_* flags removed - these are now handled by enablement.yaml files
    addons = {
      # Cluster Categorization
      fleet_member = "control-plane"
      environment  = lookup(local.config, "environment", lookup(lookup(local.config, "tags", {}), "Environment", local.hub_alias))
      tenant       = lookup(local.config, "tenant", local.hub_alias)  # tenant=hub_alias for hub
    }
    metadata = {
      annotations = merge(
        {
          # Repository Configuration (static)
          hub_repo_url         = local.hub_repo_url
          hub_repo_revision    = local.gitops_branch
          hub_repo_basepath    = local.hub_repo_basepath
          addons_repo_url      = local.hub_repo_url
          addons_repo_revision = local.gitops_branch
          addons_repo_basepath = local.addons_repo_basepath
          rgds_repo_url        = local.argocd_gitops.rgds.repo_url
          rgds_path            = local.rgds_gitops_argocd_path
          branch               = local.gitops_branch
          bootstrap_path       = local.gitops_bootstrap_path

          # Cluster Information (static)
          hub_cluster_name = local.cluster_name
          hub_alias        = local.hub_alias
          hub_aws_region   = local.aws_region
          aws_region       = local.aws_region

          # IAM Repository (for future IAM sync jobs)
          iam_repo_url = local.iam_repo_url_base
        },
        # ACK controller namespace annotations
        { for name, cfg in local.hub_ack_configs :
          "ack_${name}_namespace" => lookup(cfg, "namespace", "ack-system")
        },
        # ACK controller service account annotations
        { for name, cfg in local.hub_ack_configs :
          "ack_${name}_service_account" => lookup(cfg, "service_account", "ack-${name}-sa")
        },
        # Addon namespace annotations
        { for name, cfg in local.addon_configs :
          "${replace(name, "_", "-")}_namespace" => lookup(cfg, "namespace", name)
        },
        # Addon service account annotations
        { for name, cfg in local.addon_configs :
          "${replace(name, "_", "-")}_service_account" => lookup(cfg, "service_account", name)
        }
        # Note: IAM role ARN annotations (ack_*_hub_role_arn, *_irsa_role_arn) will be added
        # by the argocd module or via a second terragrunt pass after pod identities are created.
        # For now, these are omitted to avoid circular dependencies.
      )
    }
    gitops_context = local.argocd_gitops  # ArgoCD GitOps metadata for cross-account access
  }

  # ArgoCD ConfigMap data structure (will be populated with module outputs)
  # This will be passed to the argocd module to create the ConfigMap
  # Kubernetes provider configuration
  hub_exec_args_base = [
    "eks",
    "get-token",
    "--cluster-name",
    local.cluster_name,
    "--region",
    local.aws_region
  ]

  hub_exec_args = local.aws_profile != "" ? concat(local.hub_exec_args_base, ["--profile", local.aws_profile]) : local.hub_exec_args_base

  # Try to load spoke ARN inputs from JSON files per spoke and controller
  spoke_arn_inputs = {
    for spoke in local.spokes : spoke.alias => {
      for controller_name in keys(local.hub_ack_configs) : controller_name =>
      try(
        jsondecode(file("${local.repo_root}/terraform/combinations/iam/gen3-kro/${spoke.alias}/ack-spoke-arns-${controller_name}.json")),
        null
      )
    }
  }
}

generate "data_sources" {
  path      = "data.auto.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
data "aws_eks_cluster" "cluster" {
  count = var.enable_argocd && var.enable_eks_cluster ? 1 : 0
  name  = var.cluster_name

  depends_on = [module.eks_cluster]
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.enable_argocd && var.enable_eks_cluster ? 1 : 0
  name  = var.cluster_name

  depends_on = [module.eks_cluster]
}
EOF
}

generate "providers" {
  path      = "providers.auto.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
provider "aws" {
  region  = "${local.aws_region}"
  profile = "${local.aws_profile}"

  default_tags {
    tags = ${jsonencode(local.base_tags)}
  }
}

${join("\n\n", [for spoke in local.spokes : <<-SPOKE
provider "aws" {
  alias   = "${spoke.alias}"
  region  = "${spoke.region}"
  profile = "${lookup(spoke, "profile", "")}"

  default_tags {
    tags = ${jsonencode(merge(local.base_tags, lookup(spoke, "tags", {}), { Spoke = spoke.alias }))}
  }
}
SPOKE
])}
EOF
}

inputs = {
  # Base configuration
  tags         = local.base_tags
  cluster_name = local.cluster_name

  # VPC configuration
  enable_vpc             = local.enable_vpc
  vpc_name               = local.vpc_name
  vpc_cidr               = local.vpc_cidr
  enable_nat_gateway     = local.enable_nat_gateway
  single_nat_gateway     = local.single_nat_gateway
  vpc_tags               = {}
  public_subnet_tags     = {}
  private_subnet_tags    = {}
  existing_vpc_id        = local.existing_vpc_id
  existing_subnet_ids    = local.existing_subnet_ids
  # Explicit subnet configuration provided via module variables
  availability_zones     = local.availability_zones
  private_subnet_cidrs   = local.private_subnet_cidrs
  public_subnet_cidrs    = local.public_subnet_cidrs

  # EKS configuration
  enable_eks_cluster                       = local.enable_eks_cluster
  cluster_version                          = local.cluster_version
  cluster_endpoint_public_access           = local.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = local.enable_cluster_creator_admin_permissions
  eks_cluster_tags                         = {}
  cluster_compute_config                   = local.cluster_compute_config

  # Addon configurations (structured from config.yaml)
  addon_configs = local.addon_configs

  # ACK configurations (structured from config.yaml)
  ack_configs = local.hub_ack_configs

  # Enable flags (computed)
  enable_ack              = local.enable_ack
  enable_multi_acct       = local.enable_multi_acct
  enable_ack_spoke_roles  = local.enable_ack_spoke_roles

  # Spoke ARN inputs (loaded from JSON files or empty)
  spoke_arn_inputs = local.spoke_arn_inputs

  # IAM Git configuration
  iam_git_repo_url = local.iam_git_url
  iam_git_branch   = local.iam_git_branch
  iam_base_path    = local.iam_base_path
  iam_raw_base_url = local.iam_raw_base_url  # Raw file base URL for HTTP fetching
  iam_repo_root    = local.repo_root  # Absolute path to repository root for local policy files

  # ArgoCD configuration
  enable_argocd      = local.enable_argocd
  argocd_config      = local.argocd_config
  argocd_install     = true
  argocd_cluster     = local.argocd_cluster
  argocd_outputs_dir = local.outputs_dir
  argocd_namespace   = local.argocd_namespace
}

# ArgoCD providers and module generation
generate "hub_kubernetes_provider" {
  path      = "kubernetes_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (local.enable_argocd ? <<-EOF
provider "kubernetes" {
  host                   = try(data.aws_eks_cluster.cluster[0].endpoint, "")
  cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data), "")

  token = try(data.aws_eks_cluster_auth.cluster[0].token, "")
}
EOF
: "")
}

generate "hub_helm_provider" {
  path      = "helm_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (local.enable_argocd ? <<-EOF
provider "helm" {
  kubernetes = {
    host                   = try(data.aws_eks_cluster.cluster[0].endpoint, "")
    cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data), "")
    token                  = try(data.aws_eks_cluster_auth.cluster[0].token, "")
  }
}
EOF
: "")
}

generate "spokes" {
  path      = "spokes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (local.enable_ack_spoke_roles ? join("\n\n", [
    for spoke in local.spokes :
    <<-EOF
# Local variables to collect hub pod identity ARNs
locals {
  hub_pod_identity_arns_${spoke.alias} = {
    ${join("\n    ", [for controller_name in keys(local.hub_ack_configs) : "\"${controller_name}\" = try(module.pod_identities[\"ack-${controller_name}\"].role_arn, \"\")"])}
  }

  hub_addon_pod_identity_arns_${spoke.alias} = {
    ${join("\n    ", [for addon_name in keys(local.addon_configs) : "\"${addon_name}\" = try(module.pod_identities[\"${addon_name}\"].role_arn, \"\")"])}
  }
}

module "spoke_${spoke.alias}" {
  source = "../../combinations/spoke"

  providers = {
    aws = aws.${spoke.alias}
  }

  tags                  = ${jsonencode(merge(local.base_tags, lookup(spoke, "tags", {}), { Spoke = spoke.alias, caller_level = "spoke_${spoke.alias}" }))}
  cluster_name          = var.cluster_name
  spoke_alias           = "${spoke.alias}"

  # ACK configuration
  ack_configs           = ${jsonencode(lookup(spoke, "ack_configs", {}))}
  hub_ack_configs       = ${jsonencode(local.hub_ack_configs)}
  hub_pod_identity_arns = local.hub_pod_identity_arns_${spoke.alias}

  # Addon configuration
  addon_configs                = ${jsonencode(lookup(spoke, "addon_configs", {}))}
  hub_addon_configs            = ${jsonencode(local.addon_configs)}
  hub_addon_pod_identity_arns  = local.hub_addon_pod_identity_arns_${spoke.alias}

  # IAM Git configuration (same as hub)
  iam_git_repo_url  = var.iam_git_repo_url
  iam_git_branch    = var.iam_git_branch
  iam_base_path     = var.iam_base_path
  iam_raw_base_url  = var.iam_raw_base_url
  iam_repo_root     = var.iam_repo_root

  depends_on = [module.pod_identities]
}
EOF
  ]) : "")
}

generate "spoke_outputs" {
  path      = "spoke_outputs.tf"
  if_exists = "overwrite_terragrunt"
  contents  = (local.enable_ack_spoke_roles && length(local.spokes) > 0 ? <<-EOF
###############################################################################
# Spoke Role Outputs
# Dynamically generated outputs for each spoke's ACK and addon roles
###############################################################################

${join("\n\n", [for spoke in local.spokes : <<-SPOKE
# Spoke: ${spoke.alias}
output "spoke_${spoke.alias}_ack_roles" {
  description = "All ACK roles for spoke ${spoke.alias} (created + override)"
  value       = try(module.spoke_${spoke.alias}.ack_all_roles, {})
}

output "spoke_${spoke.alias}_addon_roles" {
  description = "All addon roles for spoke ${spoke.alias} (created + override)"
  value       = try(module.spoke_${spoke.alias}.addon_all_roles, {})
}

output "spoke_${spoke.alias}_ack_created_roles" {
  description = "Created ACK roles for spoke ${spoke.alias}"
  value       = try(module.spoke_${spoke.alias}.ack_spoke_roles, {})
}

output "spoke_${spoke.alias}_addon_created_roles" {
  description = "Created addon roles for spoke ${spoke.alias}"
  value       = try(module.spoke_${spoke.alias}.addon_spoke_roles, {})
}

output "spoke_${spoke.alias}_ack_override_arns" {
  description = "ACK override ARNs for spoke ${spoke.alias}"
  value       = try(module.spoke_${spoke.alias}.ack_override_arns, {})
}

output "spoke_${spoke.alias}_addon_override_arns" {
  description = "Addon override ARNs for spoke ${spoke.alias}"
  value       = try(module.spoke_${spoke.alias}.addon_override_arns, {})
}
SPOKE
])}

# Combined spoke roles output (all spokes)
output "all_spoke_ack_roles" {
  description = "All ACK roles across all spokes"
  value = merge(
${join(",\n", [for spoke in local.spokes : "    try(module.spoke_${spoke.alias}.ack_all_roles, {})"])}
  )
}

output "all_spoke_addon_roles" {
  description = "All addon roles across all spokes"
  value = merge(
${join(",\n", [for spoke in local.spokes : "    try(module.spoke_${spoke.alias}.addon_all_roles, {})"])}
  )
}
EOF
  : "")
}
