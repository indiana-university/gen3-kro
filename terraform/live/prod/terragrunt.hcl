# terraform/live/prod/terragrunt.hcl
# Production environment configuration
# This environment deploys the EKS hub cluster with cross-account IAM enabled

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  # Load root configuration
  root_config = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  config      = local.root_config.locals.config

  # Extract configuration sections
  hub        = local.config.hub
  ack        = local.config.ack
  spokes     = local.config.spokes
  gitops     = local.config.gitops
  deployment = local.config.deployment
  addons     = local.config.addons
  common_tags = local.root_config.locals.common_tags

  # Production-specific settings
  deployment_stage         = "prod"
  enable_cross_account_iam = true

  # Output directory
  repo_root   = get_repo_root()
  outputs_dir = "${local.repo_root}/${local.config.paths.outputs_dir}/prod"
}

# Point to root module
terraform {
  source = "${get_repo_root()}/terraform//modules/root"
}

# Generate Kubernetes and Helm providers (these need cluster info, so generated here)
generate "kube_providers" {
  path      = "kube_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    # Data source to lookup existing cluster (will be null if cluster doesn't exist yet)
    # This allows Terraform to work whether cluster exists or is being created
    data "aws_eks_cluster" "cluster" {
      name = "${local.hub.cluster_name}"
    }

    data "aws_eks_cluster_auth" "cluster" {
      name = "${local.hub.cluster_name}"
    }

    # Kubernetes provider - EKS authentication
    provider "kubernetes" {
      # Use data source instead of module output to avoid circular dependency
      host                   = data.aws_eks_cluster.cluster.endpoint
      cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
      token                  = data.aws_eks_cluster_auth.cluster.token

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", "${local.hub.cluster_name}",
          "--region", "${local.hub.aws_region}",
          "--profile", "${local.hub.aws_profile}"
        ]
      }
    }

    # Helm provider
    provider "helm" {
      kubernetes = {
        host                   = data.aws_eks_cluster.cluster.endpoint
        cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
        token                  = data.aws_eks_cluster_auth.cluster.token

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args = [
            "eks", "get-token",
            "--cluster-name", "${local.hub.cluster_name}",
            "--region", "${local.hub.aws_region}",
            "--profile", "${local.hub.aws_profile}"
          ]
        }
      }
    }

    # Kubectl provider
    provider "kubectl" {
      host                   = data.aws_eks_cluster.cluster.endpoint
      cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
      token                  = data.aws_eks_cluster_auth.cluster.token
      load_config_file       = false

      exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", "${local.hub.cluster_name}",
          "--region", "${local.hub.aws_region}",
          "--profile", "${local.hub.aws_profile}"
        ]
      }
    }
  EOF
}

# Generate IAM Access module calls dynamically for each spoke
generate "iam_access_modules" {
  path      = "iam-access-modules.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    %{for spoke in local.spokes~}
    module "iam-access-${spoke.alias}" {
      source = "../iam-access"

      ack_services_config   = local.ack_services_config
      ack_services          = var.ack_services
      environment           = local.environment
      user_provided_inline_policy_link = var.user_provided_inline_policy_link
      hub_account_id        = local.hub_account_id
      cluster_info          = local.cluster_info
      tags                  = local.tags
      alias_tag             = "${spoke.alias}"
      spoke_alias           = "${spoke.alias}"
      spoke_account_id      = "${try(spoke.account_id, "")}"
      # For prod: if spoke has account_id specified and different, it's external
      # Otherwise it's internal (same account as hub)
      enable_external_spoke = ${try(spoke.account_id, "") != "" ? "true" : "false"}
      enable_internal_spoke = ${try(spoke.account_id, "") == "" ? "true" : "false"}

      providers = {
        aws.spoke = aws.${spoke.alias}
      }

      depends_on = [module.eks-hub]
    }
    %{endfor~}

    # Collect outputs from all IAM access modules
    locals {
      ack_spoke_role_arns_by_spoke = {
        %{for spoke in local.spokes~}
        "${spoke.alias}" = module.iam-access-${spoke.alias}.ack_spoke_role_arns
        %{endfor~}
      }

      iam_access_modules_data = {
        %{for spoke in local.spokes~}
        "${spoke.alias}" = {
          account_id = module.iam-access-${spoke.alias}.account_id
          ack_spoke_role_arns = module.iam-access-${spoke.alias}.ack_spoke_role_arns
        }
        %{endfor~}
      }
    }
  EOF
}
# Input variables for root module
inputs = {
  # Hub configuration from config.yaml
  hub_aws_profile    = local.hub.aws_profile
  hub_aws_region     = local.hub.aws_region
  cluster_name       = local.hub.cluster_name
  kubernetes_version = local.hub.kubernetes_version
  vpc_name           = local.hub.vpc_name
  kubeconfig_dir     = local.deployment.kubeconfig_dir

  # Deployment configuration from config.yaml
  deployment_stage         = local.deployment_stage
  enable_cross_account_iam = local.enable_cross_account_iam
  argocd_chart_version     = local.deployment.argocd_chart_version
  user_provided_inline_policy_link = local.ack.user_provided_inline_policy_link
  # ACK configuration from config.yaml
  ack_services = local.ack.controllers
  use_ack      = true

  # Spokes configuration from config.yaml
  spokes = [
    for spoke in local.spokes : {
      alias   = spoke.alias
      region  = spoke.region
      profile = spoke.profile
      tags    = merge(try(spoke.tags, {}), { Environment = "production" })
    }
  ]

  # Addons configuration from config.yaml
  addons = local.addons

  # GitOps Addons configuration from config.yaml
  gitops_addons_github_url               = local.gitops.github_url
  gitops_addons_org_name                 = local.gitops.org_name
  gitops_addons_repo_name                = local.gitops.repo_name
  gitops_addons_repo_base_path           = local.gitops.addons.base_path
  gitops_addons_repo_path                = local.gitops.addons.path
  gitops_addons_repo_revision            = local.gitops.addons.revision
  gitops_iam_config_raw_file_base_url               = try(local.gitops.iam_config_raw_file_base_url, "")
  gitops_addons_app_id                   = ""
  gitops_addons_app_installation_id      = ""
  gitops_addons_app_private_key_ssm_path = ""

  # GitOps Fleet configuration from config.yaml
  gitops_fleet_github_url               = local.gitops.github_url
  gitops_fleet_org_name                 = local.gitops.org_name
  gitops_fleet_repo_name                = local.gitops.repo_name
  gitops_fleet_repo_base_path           = local.gitops.fleet.base_path
  gitops_fleet_repo_path                = local.gitops.fleet.path
  gitops_fleet_repo_revision            = local.gitops.fleet.revision
  gitops_fleet_app_id                   = ""
  gitops_fleet_app_installation_id      = ""
  gitops_fleet_app_private_key_ssm_path = ""

  # GitOps Platform configuration from config.yaml
  gitops_platform_github_url               = local.gitops.github_url
  gitops_platform_org_name                 = local.gitops.org_name
  gitops_platform_repo_name                = local.gitops.repo_name
  gitops_platform_repo_base_path           = local.gitops.platform.base_path
  gitops_platform_repo_path                = local.gitops.platform.path
  gitops_platform_repo_revision            = local.gitops.platform.revision
  gitops_platform_app_id                   = ""
  gitops_platform_app_installation_id      = ""
  gitops_platform_app_private_key_ssm_path = ""

  # GitOps Workload configuration from config.yaml
  gitops_workload_github_url               = local.gitops.github_url
  gitops_workload_org_name                 = local.gitops.org_name
  gitops_workload_repo_name                = local.gitops.repo_name
  gitops_workload_repo_base_path           = local.gitops.workload.base_path
  gitops_workload_repo_path                = local.gitops.workload.path
  gitops_workload_repo_revision            = local.gitops.workload.revision
  gitops_workload_app_id                   = ""
  gitops_workload_app_installation_id      = ""
  gitops_workload_app_private_key_ssm_path = ""

  # Output paths
  outputs_dir = local.outputs_dir

  # Tags
  tags = merge(
    local.common_tags,
    {
      Environment     = "production"
      DeploymentStage = local.deployment_stage
      CostCenter      = "platform-engineering"
    }
  )
}

# Dependencies (none for now, but can be added for multi-module setups)
dependencies {
  paths = []
}
