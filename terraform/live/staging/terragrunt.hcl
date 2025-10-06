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
  common_tags = local.root_config.locals.common_tags
  
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
      host                   = try(module.eks-hub.cluster_endpoint, "")
      cluster_ca_certificate = try(base64decode(module.eks-hub.cluster_certificate_authority_data), "")
      
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
    
    provider "helm" {
      kubernetes = {
        host                   = try(module.eks-hub.cluster_endpoint, "")
        cluster_ca_certificate = try(base64decode(module.eks-hub.cluster_certificate_authority_data), "")
        
        exec = {
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
    }
    
    provider "kubectl" {
      host                   = try(module.eks-hub.cluster_endpoint, "")
      cluster_ca_certificate = try(base64decode(module.eks-hub.cluster_certificate_authority_data), "")
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

inputs = {
  hub_aws_profile    = local.hub.aws_profile
  hub_aws_region     = local.hub.aws_region
  cluster_name       = local.cluster_name
  kubernetes_version = local.hub.kubernetes_version
  vpc_name           = local.vpc_name
  
  deployment_stage         = local.deployment_stage
  enable_cross_account_iam = local.enable_cross_account_iam
  
  ack_services = local.ack.controllers
  use_ack      = true
  
  spokes = [
    for spoke in local.spokes : {
      alias      = spoke.alias
      region     = spoke.region
      profile    = spoke.profile
      account_id = try(spoke.account_id, "")
      tags       = merge(try(spoke.tags, {}), { Environment = "staging" })
    }
  ]
  
  addons = local.addons
  
  # GitOps configurations with staging branch
  gitops_addons_github_url     = "github.com"
  gitops_addons_org_name       = local.gitops.org_name
  gitops_addons_repo_name      = local.gitops.repo_name
  gitops_addons_repo_base_path = local.gitops.addons.base_path
  gitops_addons_repo_path      = local.gitops.addons.path
  gitops_addons_repo_revision  = "staging"  # Use staging branch
  gitops_addons_app_id                   = ""
  gitops_addons_app_installation_id      = ""
  gitops_addons_app_private_key_ssm_path = ""
  
  gitops_fleet_github_url     = "github.com"
  gitops_fleet_org_name       = local.gitops.org_name
  gitops_fleet_repo_name      = local.gitops.repo_name
  gitops_fleet_repo_base_path = local.gitops.fleet.base_path
  gitops_fleet_repo_path      = local.gitops.fleet.path
  gitops_fleet_repo_revision  = "staging"
  gitops_fleet_app_id                   = ""
  gitops_fleet_app_installation_id      = ""
  gitops_fleet_app_private_key_ssm_path = ""
  
  gitops_platform_github_url     = "github.com"
  gitops_platform_org_name       = local.gitops.org_name
  gitops_platform_repo_name      = local.gitops.repo_name
  gitops_platform_repo_base_path = local.gitops.platform.base_path
  gitops_platform_repo_path      = local.gitops.platform.path
  gitops_platform_repo_revision  = "staging"
  gitops_platform_app_id                   = ""
  gitops_platform_app_installation_id      = ""
  gitops_platform_app_private_key_ssm_path = ""
  
  gitops_workload_github_url     = "github.com"
  gitops_workload_org_name       = local.gitops.org_name
  gitops_workload_repo_name      = local.gitops.repo_name
  gitops_workload_repo_base_path = local.gitops.workload.base_path
  gitops_workload_repo_path      = local.gitops.workload.path
  gitops_workload_repo_revision  = "staging"
  gitops_workload_app_id                   = ""
  gitops_workload_app_installation_id      = ""
  gitops_workload_app_private_key_ssm_path = ""
  
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
