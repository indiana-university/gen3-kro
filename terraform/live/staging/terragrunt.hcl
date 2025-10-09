# terraform/live/staging/terragrunt.hcl
# Staging environment configuration
# This environment is for testing before production deployment

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
  addons     = local.config.addons
  deployment = local.config.deployment
  common_tags = local.root_config.locals.common_tags
  user_provided_inline_policy_link = local.ack.user_provided_inline_policy_link
  # Staging-specific settings
  deployment_stage         = "staging"
  enable_cross_account_iam = false  # Same account for staging

  # Modify cluster name for staging
  cluster_name = "${local.hub.cluster_name}-staging"
  vpc_name     = "${local.hub.vpc_name}-staging"

  # Output directory
  repo_root   = get_repo_root()
  outputs_dir = "${local.repo_root}/${local.config.paths.outputs_dir}/staging"
}

terraform {
  source = "${get_repo_root()}/terraform//modules/root"
}

# Generate Kubernetes and Helm providers
generate "kube_providers" {
  path      = "kube_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = module.eks-hub.cluster_info.cluster_endpoint
      cluster_ca_certificate = base64decode(module.eks-hub.cluster_info.cluster_certificate_authority_data)

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks",
          "get-token",
          "--cluster-name", "${local.cluster_name}",
          "--region", "${local.hub.aws_region}",
          "--profile", "${local.hub.aws_profile}"
        ]
      }
    }

    provider "helm" {
      kubernetes = {
        host                   = module.eks-hub.cluster_info.cluster_endpoint
        cluster_ca_certificate = base64decode(module.eks-hub.cluster_info.cluster_certificate_authority_data)

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args = [
            "eks",
            "get-token",
            "--cluster-name", "${local.cluster_name}",
            "--region", "${local.hub.aws_region}",
            "--profile", "${local.hub.aws_profile}"
          ]
        }
      }
    }

    provider "kubectl" {
      host                   = module.eks-hub.cluster_info.cluster_endpoint
      cluster_ca_certificate = base64decode(module.eks-hub.cluster_info.cluster_certificate_authority_data)
      load_config_file       = false

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", "${local.cluster_name}",
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

      ack_services                     = var.ack_services
      environment                      = local.environment
      cluster_info                     = local.cluster_info
      ack_hub_roles                    = local.ack_hub_roles
      tags                             = local.tags
      alias_tag                        = "${spoke.alias}"
      spoke_alias                      = "${spoke.alias}"

      # For staging, all spokes are internal (same account)
      enable_external_spoke = false
      enable_internal_spoke = true

      providers = {
        aws.hub   = aws.hub
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
inputs = {
  # Hub configuration from config.yaml
  hub_alias          = local.hub.alias
  hub_aws_profile    = local.hub.aws_profile
  hub_aws_region     = local.hub.aws_region
  cluster_name       = local.cluster_name
  kubernetes_version = local.hub.kubernetes_version
  vpc_name           = local.vpc_name
  kubeconfig_dir     = local.deployment.kubeconfig_dir

  # Deployment configuration from config.yaml
  deployment_stage         = local.deployment_stage
  enable_cross_account_iam = local.enable_cross_account_iam
  argocd_chart_version     = local.deployment.argocd_chart_version

  # ACK configuration from config.yaml
  ack_services = local.ack.controllers
  use_ack      = true

  # Spokes configuration from config.yaml
  spokes = [
    for spoke in local.spokes : {
      alias   = spoke.alias
      region  = spoke.region
      profile = spoke.profile
      tags    = merge(try(spoke.tags, {}), { Environment = "staging" })
    }
  ]

  # Addons configuration from config.yaml
  addons = local.addons

  # GitOps configurations from config.yaml with staging branch
  # All repos use the same GitHub instance and organization
  gitops_addons_github_url     = local.gitops.github_url
  gitops_addons_org_name       = local.gitops.org_name
  gitops_addons_repo_name      = local.gitops.repo_name
  gitops_addons_repo_base_path = local.gitops.addons.base_path
  gitops_addons_repo_path      = local.gitops.addons.path
  gitops_addons_repo_revision  = "staging"
  gitops_addons_app_id                   = ""
  gitops_addons_app_installation_id      = ""
  gitops_addons_app_private_key_ssm_path = ""

  gitops_fleet_github_url     = local.gitops.github_url
  gitops_fleet_org_name       = local.gitops.org_name
  gitops_fleet_repo_name      = local.gitops.repo_name
  gitops_fleet_repo_base_path = local.gitops.fleet.base_path
  gitops_fleet_repo_path      = local.gitops.fleet.path
  gitops_fleet_repo_revision  = "staging"
  gitops_fleet_app_id                   = ""
  gitops_fleet_app_installation_id      = ""
  gitops_fleet_app_private_key_ssm_path = ""

  gitops_platform_github_url     = local.gitops.github_url
  gitops_platform_org_name       = local.gitops.org_name
  gitops_platform_repo_name      = local.gitops.repo_name
  gitops_platform_repo_base_path = local.gitops.platform.base_path
  gitops_platform_repo_path      = local.gitops.platform.path
  gitops_platform_repo_revision  = "staging"
  gitops_platform_app_id                   = ""
  gitops_platform_app_installation_id      = ""
  gitops_platform_app_private_key_ssm_path = ""

  gitops_workload_github_url     = local.gitops.github_url
  gitops_workload_org_name       = local.gitops.org_name
  gitops_workload_repo_name      = local.gitops.repo_name
  gitops_workload_repo_base_path = local.gitops.workload.base_path
  gitops_workload_repo_path      = local.gitops.workload.path
  gitops_workload_repo_revision  = "staging"
  gitops_workload_app_id                   = ""
  gitops_workload_app_installation_id      = ""
  gitops_workload_app_private_key_ssm_path = ""

  # IAM config raw file base URL for ACK controller policy templates
  gitops_iam_config_raw_file_base_url = try(local.gitops.iam_config_raw_file_base_url, "")

  outputs_dir = local.outputs_dir

  tags = merge(
    local.common_tags,
    {
      Environment     = "staging"
      DeploymentStage = local.deployment_stage
      CostCenter      = "platform-engineering"
    }
  )
}
