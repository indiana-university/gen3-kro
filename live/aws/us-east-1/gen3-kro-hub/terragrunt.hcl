include {
  path = find_in_parent_folders("backend.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform//combinations/hub"
}

locals {
  ###################################################################################################################################################
  # DATA IMPORT SECTION - Imports variables from config.yaml
  ###################################################################################################################################################
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
  vpc_config         = lookup(local.hub_config, "vpc", {})
  enable_vpc         = lookup(local.vpc_config, "enable_vpc", false)
  vpc_name           = lookup(local.vpc_config, "vpc_name", "")
  vpc_cidr           = lookup(local.vpc_config, "vpc_cidr", "10.0.0.0/16")
  enable_nat_gateway = lookup(local.vpc_config, "enable_nat_gateway", false)
  single_nat_gateway = lookup(local.vpc_config, "single_nat_gateway", false)
  existing_vpc_id    = lookup(local.vpc_config, "existing_vpc_id", "")
  existing_subnet_ids = lookup(local.vpc_config, "existing_subnet_ids", [])

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
  iam_gitops_config            = lookup(local.hub_config, "iam_gitops", {})
  iam_gitops_org_name          = lookup(local.iam_gitops_config, "org_name", "")
  iam_gitops_repo_name         = lookup(local.iam_gitops_config, "repo_name", "")
  iam_gitops_github_url        = lookup(local.iam_gitops_config, "github_url", "github.com")
  iam_gitops_branch            = lookup(local.iam_gitops_config, "branch", "main")
  iam_gitops_private_repo_path = lookup(local.iam_gitops_config, "iam_policy_private_repo_path", "")
  iam_gitops_version           = lookup(local.iam_gitops_config, "version", "0.1.0")

  # Addon configurations from hub.addon_configs
  addon_configs = lookup(local.hub_config, "addon_configs", {})

  # ACK configurations from hub.ack_configs
  hub_ack_configs = lookup(local.hub_config, "ack_configs", {})

  # Paths configuration
  outputs_dir            = lookup(local.paths_config, "outputs_dir", "./outputs")
  terraform_state_bucket = lookup(local.paths_config, "terraform_state_bucket", "")
  terraform_locks_table  = lookup(local.paths_config, "terraform_locks_table", "")

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

  # ArgoCD configuration objects
  argocd_config = {
    namespace     = local.argocd_namespace
    chart         = "argo-cd"
    repository    = "https://argoproj.github.io/argo-helm"
    chart_version = local.argocd_chart_version
    values        = []
  }

  argocd_cluster = {
    cluster_name     = local.cluster_name
    secret_namespace = local.argocd_namespace
    metadata = {
      annotations = {
        hub_repo_url   = local.hub_repo_url
        bootstrap_path = local.gitops_bootstrap_path
        branch         = local.gitops_branch
      }
      labels = {
        fleet_member = "control-plane"
      }
    }
    addons = {}  # Addons now managed via addon_configs
  }

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
        jsondecode(file("${local.repo_root}/iam/gen3-kro/${spoke.alias}/ack-spoke-arns-${controller_name}.json")),
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
}

data "aws_eks_cluster_auth" "cluster" {
  count = var.enable_argocd && var.enable_eks_cluster ? 1 : 0
  name  = var.cluster_name
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
  enable_vpc          = local.enable_vpc
  vpc_name            = local.vpc_name
  vpc_cidr            = local.vpc_cidr
  enable_nat_gateway  = local.enable_nat_gateway
  single_nat_gateway  = local.single_nat_gateway
  vpc_tags            = {}
  public_subnet_tags  = {}
  private_subnet_tags = {}
  existing_vpc_id     = local.existing_vpc_id
  existing_subnet_ids = local.existing_subnet_ids

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

  # ArgoCD configuration
  enable_argocd      = local.enable_argocd
  argocd_config      = local.argocd_config
  argocd_install     = true
  argocd_cluster     = local.argocd_cluster
  argocd_apps        = {}
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

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ${jsonencode(local.hub_exec_args)}
  }
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
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ${jsonencode(local.hub_exec_args)}
    }
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
module "spoke_${spoke.alias}" {
  source = "../spoke-iam"

  providers = {
    aws = aws.${spoke.alias}
  }

  tags           = ${jsonencode(merge(local.base_tags, lookup(spoke, "tags", {}), { Spoke = spoke.alias, caller_level = "spoke_${spoke.alias}" }))}
  cluster_name   = var.cluster_name
  spoke_alias    = "${spoke.alias}"
  ack_configs    = ${jsonencode(lookup(spoke, "ack_configs", {}))}
  hub_ack_configs = ${jsonencode(local.hub_ack_configs)}
}
EOF
  ]) : "")
}
