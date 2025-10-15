###################################################################################################################################################
# Terragrunt Stack Configuration for gen3-kro Hub Cluster
###################################################################################################################################################

locals {
  # Load stack configuration from config.yaml
  stack_config = yamldecode(file("terragrunt.yaml"))

  # Paths
  repo_root  = get_repo_root()
  units_path = "${local.repo_root}/units"
  outputs_dir = "${local.paths.outputs_dir}/terragrunt"

  # Extract configuration sections
  hub    = local.stack_config.hub
  ack    = local.stack_config.ack
  spokes = local.stack_config.spokes
  addons = local.stack_config.addons
  gitops = local.stack_config.gitops
  paths  = local.stack_config.paths

  # Hub-cluster Addons Configuration
  external_secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets-sa"
  }

  aws_load_balancer_controller = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller-sa"
  }

  # ACK Services configuration
  ack_services = toset(local.ack.controllers)
  ack_services_config = {
    for service in local.ack_services : service => {
      namespace       = local.ack.namespace
      service_account = "${service}-ack-controller-sa"
    }
  }

  # GitOps URLs
  gitops_hub_repo_url    = "https://${local.gitops.github_url}/${local.gitops.org_name}/${local.gitops.repo_name}"
  gitops_rgds_repo_url   = "https://${local.gitops.github_url}/${local.gitops.org_name}/${local.gitops.repo_name}"
  gitops_spokes_repo_url = "https://${local.gitops.github_url}/${local.gitops.org_name}/${local.gitops.repo_name}"

  # Common tags
  common_tags = {
    Project     = "gen3-kro"
    ManagedBy   = "Terragrunt"
    Owner       = "RDS"
  }
}

  cluster_version = var.cluster_version
  hub_region      = var.hub_region
  vpc_id          = var.vpc_id
  use_ack         = var.use_ack

  # ArgoCD configuration from variables
  argocd_namespace                     = var.argocd_namespace
  argocd_chart_version                 = var.argocd_chart_version
  argocd_hub_pod_identity_iam_role_arn = var.argocd_hub_pod_identity_iam_role_arn

  # GitOps configuration from variables
  gitops_hub_repo_url    = var.gitops_hub_repo_url
  gitops_rgds_repo_url   = var.gitops_rgds_repo_url
  gitops_spokes_repo_url = var.gitops_spokes_repo_url
  gitops_branch          = var.gitops_branch
  gitops_bootstrap_path  = var.gitops_bootstrap_path
  gitops_rgds_path       = var.gitops_rgds_path
  gitops_spokes_path     = var.gitops_spokes_path

  # External Secrets configuration
  external_secrets             = var.external_secrets
  aws_load_balancer_controller = var.aws_load_balancer_controller

  # ACK configuration from variables
  ack_services_config = var.ack_services_config
  ack_hub_roles       = var.ack_hub_roles

  # IAM spoke data from unit outputs
  ack_spoke_role_arns_by_spoke = {
    for spoke_alias, spoke_data in var.iam_spoke_outputs :
    spoke_alias => spoke_data.ack_spoke_role_arns
  }

  iam_access_modules_data = var.iam_spoke_outputs

  # Fleet member flag
  fleet_member = true


  # canonical keys expected by downstream templates / ApplicationSets


  argocd_apps = {
    applicationsets = file("applicationsets.yaml")
  }

  argocd_cluster_data = {
    cluster_name = local.hub.cluster_name

    addons       = merge(
      { fleet_member       = "control-plane" },
      { kubernetes_version = local.hub.cluster_version },
      { cluster_name   = local.hub.cluster_name }
    )

    metadata     =  merge(
      {
        hub_account_id   = var.hub_account_id
        hub_cluster_name = local.hub.cluster_name
        hub_aws_region   = local.hub_region
        aws_vpc_id       = local.vpc_id
        use_ack          = local.use_ack
        tenants          = yamlencode([for spoke in var.spokes : spoke.alias])
      },
      {
        argocd_namespace           = local.argocd_namespace,
        create_argocd_namespace    = false,
        argocd_controller_role_arn = local.argocd_hub_pod_identity_iam_role_arn
      },
      {
        hub_repo_url     = local.gitops_hub_repo_url
        hub_repo_revision = local.gitops_branch
        hub_repo_basepath = "argocd"
        rgds_repo_url    = local.gitops_rgds_repo_url
        spokes_repo_url  = local.gitops_spokes_repo_url
        branch           = local.gitops_branch
        bootstrap_path   = local.gitops_bootstrap_path
        rgds_path        = local.gitops_rgds_path
        spokes_path      = local.gitops_spokes_path
      },
      {
        external_secrets_namespace       = local.external_secrets.namespace
        external_secrets_service_account = local.external_secrets.service_account
      },
      {
        aws_load_balancer_controller_namespace       = local.aws_load_balancer_controller.namespace
        aws_load_balancer_controller_service_account = local.aws_load_balancer_controller.service_account
      },
      # Flatten ACK controller configs into individual annotations
      # Hub role ARNs
      {
        for service, cfg in local.ack_services_config :
        "ack_${service}_hub_role_arn" => try(local.ack_hub_roles[service].arn, "")
      },
      # Namespaces
      {
        for service, cfg in local.ack_services_config :
        "ack_${service}_namespace" => cfg.namespace
      },
      # Service accounts
      {
        for service, cfg in local.ack_services_config :
        "ack_${service}_service_account" => cfg.service_account
      },
      # Spoke role ARNs - flatten completely
      merge([
        for service, cfg in local.ack_services_config : {
          for spoke_alias, arn_maps in try(local.ack_spoke_role_arns_by_spoke, {}) :
          "ack_${service}_spoke_role_arn_${spoke_alias}" => try(arn_maps[service], "")
        }
      ]...),
      {
        for spoke_alias, spoke_data in try(local.iam_access_modules_data, {}) :
        "${spoke_alias}_account_id" => try(spoke_data.account_id, null)
      },
    )
  }

  argocd_settings = {
    name             = "argocd"
    namespace        = local.argocd_namespace
    chart_version    = local.argocd_chart_version
    values           = [file("argocd-initial-values.yaml")]
    timeout          = 600
    create_namespace = false
  }
# Terraform version constraints
terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }
}
###################################################################################################################################################
# Provider configuration
###################################################################################################################################################
# Generate provider configuration for stack
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region  = "${local.stack_config.hub.aws_region}"
      profile = "${local.stack_config.hub.aws_profile}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }
  EOF
}

###################################################################################################################################################
# Units - Deployable Components
###################################################################################################################################################
# Unit 1: EKS Hub Cluster
unit "eks_hub" {
  source = "${local.units_path}/eks-hub"
  path = "eks-hub"

  values = {
    # version = branch name
    version = local.hub.gitops.branch
    # Core configuration
    create           = true
    aws_region       = local.hub.aws_region
    vpc_name         = local.hub.vpc_name
    cluster_name     = local.hub.cluster_name
    cluster_version  = local.hub.kubernetes_version
    hub_alias        = local.hub.alias

    # VPC Configuration
    vpc_cidr = "10.0.0.0/16"

    # ACK Configuration
    ack_services        = local.ack_services
    ack_services_config = local.ack_services_config

    # Addons Configuration
    iam_settings = local.iam_settings


    external_secrets = local.external_secrets_config
    aws_load_balancer_controller = local.aws_load_balancer_controller_config
    # Tags

    tags = local.common_tags
  }
}

# Unit 2: IAM Spoke Roles (for hub as internal spoke)
generate iam_spokes {
  path      = "iam_spoke_hub.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    unit "iam_spoke_hub" {
      source = "${local.units_path}/iam-spoke"

      values = {
        ack_services        = local.ack_services
        ack_services_config = local.ack_services_config
        tags                = merge(local.common_tags, { SpokeType = "internal-hub" })
        spoke_alias         = local.hub.alias

        # Hub as internal spoke (same account)
        enable_external_spoke = false
        enable_internal_spoke = true
      }
    }
  EOF
}

# Unit 3: Multi-Cluster Computations (GitOps Metadata)
unit "argocd_computations" {
  source = "${local.units_path}/multi-cluster-computations"

  values = {
    # Cluster Information
    cluster_name    = local.hub.cluster_name
    cluster_version = local.hub.kubernetes_version
    hub_region      = local.hub.aws_region
    hub_alias       = local.hub.alias

    # ACK Configuration
    ack_services        = local.ack_services
    ack_services_config = local.ack_services_config
    use_ack             = true

    # GitOps Configuration
    gitops_hub_repo_url    = local.gitops_hub_repo_url
    gitops_rgds_repo_url   = local.gitops_rgds_repo_url
    gitops_spokes_repo_url = local.gitops_spokes_repo_url
    gitops_branch          = local.gitops.addons.revision
    gitops_bootstrap_path  = "argocd/bootstrap"
    gitops_rgds_path       = "argocd/shared/graphs"
    gitops_spokes_path     = "argocd/spokes"

    # ArgoCD Configuration
    argocd_namespace     = "argocd"
    argocd_chart_version = local.stack_config.deployment.argocd_chart_version

    # External Secrets Configuration
    external_secrets = {
      namespace       = "external-secrets"
      service_account = "external-secrets-sa"
    }

    # AWS Load Balancer Controller Configuration
    aws_load_balancer_controller = {
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller-sa"
    }

    # Spoke Configuration
    spokes = local.spokes

    # Tags
    tags = local.common_tags

    # Dependencies from eks-hub
    cluster_info                         = dependency.unit.eks_hub.outputs.cluster_info
    vpc_id                               = dependency.unit.eks_hub.outputs.vpc_id
    hub_account_id                       = dependency.unit.eks_hub.outputs.account_id
    ack_hub_roles                        = dependency.unit.eks_hub.outputs.ack_hub_roles
    argocd_hub_pod_identity_iam_role_arn = dependency.unit.eks_hub.outputs.argocd_hub_pod_identity_iam_role_arn

    # Dependencies from iam-spoke units
    iam_spoke_outputs = {
      "${local.hub.alias}" = {
        account_id          = dependency.unit.iam_spoke_hub.outputs.account_id
        ack_spoke_role_arns = dependency.unit.iam_spoke_hub.outputs.ack_spoke_role_arns
      }
    }
  }
}

# Unit 4: ArgoCD Bootstrap
unit "argocd_bootstrap" {
  source = "${local.units_path}/argocd-bootstrap"

  inputs = {
    create      = local.addons.enable_argocd
    install     = local.addons.enable_argocd
    outputs_dir = local.paths.outputs_dir

    # Dependencies from multi-cluster-computations
    cluster         = dependency.unit.multi_cluster_computations.outputs.cluster
    apps            = dependency.unit.multi_cluster_computations.outputs.argocd_apps
    argocd          = dependency.unit.multi_cluster_computations.outputs.argocd_settings
    addons_metadata = dependency.unit.multi_cluster_computations.outputs.addons_metadata
  }
}

###################################################################################################################################################
# End of Stack Configuration
###################################################################################################################################################
