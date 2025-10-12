include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  root_config = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  config      = local.root_config.locals.config

  hub         = local.config.hub
  ack         = local.config.ack
  spokes      = local.config.spokes
  gitops      = local.config.gitops
  deployment  = local.config.deployment
  addons      = local.config.addons
  common_tags = local.root_config.locals.common_tags

  deployment_stage         = "prod"
  enable_cross_account_iam = true

  repo_root   = get_repo_root()
  outputs_dir = "${local.repo_root}/${local.config.paths.outputs_dir}/prod"
}

# Point to root module
terraform {
  source = "${get_repo_root()}/terraform//modules/root"
}

generate "kube_providers" {
  path      = "kube_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "external" "cluster_exists" {
      program = ["bash", "-c", <<EOT
        cluster_names="${local.hub.cluster_name}"
        %{if try(local.hub.old_cluster_name, "") != ""}
        cluster_names="$cluster_names ${local.hub.old_cluster_name}"
        %{endif}

        for cluster_name in $cluster_names; do
          if aws eks describe-cluster --name "$cluster_name" --region ${local.hub.aws_region} --profile ${local.hub.aws_profile} &>/dev/null; then
            echo "{\"cluster_name\":\"$cluster_name\",\"exists\":\"true\"}"
            exit 0
          fi
        done
        echo "{\"cluster_name\":\"${local.hub.cluster_name}\",\"exists\":\"false\"}"
      EOT
      ]
    }

    locals {
      cluster_exists          = try(data.external.cluster_exists.result.exists, "false") == "true"
      active_cluster_name     = try(data.external.cluster_exists.result.cluster_name, "${local.hub.cluster_name}")
      cluster_rename_in_progress = local.cluster_exists && local.active_cluster_name != "${local.hub.cluster_name}"
    }

    data "aws_eks_cluster" "cluster" {
      count = local.cluster_exists ? 1 : 0
      name  = local.active_cluster_name
    }

    data "aws_eks_cluster_auth" "cluster" {
      count = local.cluster_exists ? 1 : 0
      name  = local.active_cluster_name
    }

    provider "kubernetes" {
      host                   = local.cluster_exists ? data.aws_eks_cluster.cluster[0].endpoint : "https://127.0.0.1:65535"
      cluster_ca_certificate = local.cluster_exists ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : null
      token                  = local.cluster_exists ? data.aws_eks_cluster_auth.cluster[0].token : null
      insecure               = !local.cluster_exists

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", local.active_cluster_name,
          "--region", "${local.hub.aws_region}",
          "--profile", "${local.hub.aws_profile}"
        ]
      }
    }

    provider "helm" {
      kubernetes = {
        host                   = local.cluster_exists ? data.aws_eks_cluster.cluster[0].endpoint : "https://127.0.0.1:65535"
        cluster_ca_certificate = local.cluster_exists ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : null
        token                  = local.cluster_exists ? data.aws_eks_cluster_auth.cluster[0].token : null
        insecure               = !local.cluster_exists

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args = [
            "eks", "get-token",
            "--cluster-name", local.active_cluster_name,
            "--region", "${local.hub.aws_region}",
            "--profile", "${local.hub.aws_profile}"
          ]
        }
      }
    }

    provider "kubectl" {
      host                   = local.cluster_exists ? data.aws_eks_cluster.cluster[0].endpoint : "https://127.0.0.1:65535"
      cluster_ca_certificate = local.cluster_exists ? base64decode(data.aws_eks_cluster.cluster[0].certificate_authority[0].data) : null
      token                  = local.cluster_exists ? data.aws_eks_cluster_auth.cluster[0].token : null
      load_config_file       = false
      insecure               = !local.cluster_exists

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", local.active_cluster_name,
          "--region", "${local.hub.aws_region}",
          "--profile", "${local.hub.aws_profile}"
        ]
      }
    }
  EOF
}

generate "iam_access_modules" {
  path      = "iam-access-modules.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    %{for spoke in local.spokes~}
    module "iam-access-${spoke.alias}" {
      source = "../iam-access"

      ack_services_config  = local.ack_services_config
      ack_services         = var.ack_services
      environment          = local.environment
      hub_account_id       = local.hub_account_id
      cluster_info         = local.cluster_info
      tags                 = local.tags
      alias_tag            = "${spoke.alias}"
      spoke_alias          = "${spoke.alias}"
      spoke_account_id     = "${try(spoke.account_id, "")}"
      enable_external_spoke = ${try(spoke.account_id, "") != "" ? "true" : "false"}
      enable_internal_spoke = ${try(spoke.account_id, "") == "" ? "true" : "false"}

      providers = {
        aws.spoke = aws.${spoke.alias}
      }

      depends_on = [module.eks-hub]
    }
    %{endfor~}

    locals {
      ack_spoke_role_arns_by_spoke = {
        %{for spoke in local.spokes~}
        "${spoke.alias}" = module.iam-access-${spoke.alias}.ack_spoke_role_arns
        %{endfor~}
      }

      iam_access_modules_data = {
        %{for spoke in local.spokes~}
        "${spoke.alias}" = {
          account_id          = module.iam-access-${spoke.alias}.account_id
          ack_spoke_role_arns = module.iam-access-${spoke.alias}.ack_spoke_role_arns
        }
        %{endfor~}
      }
    }
  EOF
}

inputs = {
  hub_alias          = local.hub.alias
  hub_aws_profile    = local.hub.aws_profile
  hub_aws_region     = local.hub.aws_region
  cluster_name       = local.hub.cluster_name
  kubernetes_version = local.hub.kubernetes_version
  vpc_name           = local.hub.vpc_name
  kubeconfig_dir     = local.deployment.kubeconfig_dir
  enable_argo        = try(local.hub.enable_argo, true)

  deployment_stage         = local.deployment_stage
  enable_cross_account_iam = local.enable_cross_account_iam
  argocd_chart_version     = local.deployment.argocd_chart_version

  ack_services = local.ack.controllers
  use_ack      = true

  spokes = local.spokes
  addons = local.addons

  gitops_addons_github_url               = local.gitops.github_url
  gitops_addons_org_name                 = local.gitops.org_name
  gitops_addons_repo_name                = local.gitops.repo_name
  gitops_addons_repo_base_path           = local.gitops.addons.base_path
  gitops_addons_repo_path                = local.gitops.addons.path
  gitops_addons_repo_revision            = local.gitops.addons.revision
  gitops_addons_app_id                   = ""
  gitops_addons_app_installation_id      = ""
  gitops_addons_app_private_key_ssm_path = ""

  gitops_fleet_github_url               = local.gitops.github_url
  gitops_fleet_org_name                 = local.gitops.org_name
  gitops_fleet_repo_name                = local.gitops.repo_name
  gitops_fleet_repo_base_path           = local.gitops.fleet.base_path
  gitops_fleet_repo_path                = local.gitops.fleet.path
  gitops_fleet_repo_revision            = local.gitops.fleet.revision
  gitops_fleet_app_id                   = ""
  gitops_fleet_app_installation_id      = ""
  gitops_fleet_app_private_key_ssm_path = ""

  gitops_platform_github_url               = local.gitops.github_url
  gitops_platform_org_name                 = local.gitops.org_name
  gitops_platform_repo_name                = local.gitops.repo_name
  gitops_platform_repo_base_path           = local.gitops.platform.base_path
  gitops_platform_repo_path                = local.gitops.platform.path
  gitops_platform_repo_revision            = local.gitops.platform.revision
  gitops_platform_app_id                   = ""
  gitops_platform_app_installation_id      = ""
  gitops_platform_app_private_key_ssm_path = ""

  gitops_workload_github_url               = local.gitops.github_url
  gitops_workload_org_name                 = local.gitops.org_name
  gitops_workload_repo_name                = local.gitops.repo_name
  gitops_workload_repo_base_path           = local.gitops.workload.base_path
  gitops_workload_repo_path                = local.gitops.workload.path
  gitops_workload_repo_revision            = local.gitops.workload.revision
  gitops_workload_app_id                   = ""
  gitops_workload_app_installation_id      = ""
  gitops_workload_app_private_key_ssm_path = ""

  gitops_iam_config_raw_file_base_url = try(local.gitops.iam_config_raw_file_base_url, "")

  outputs_dir = local.outputs_dir

  tags = merge(
    local.common_tags,
    {
      Environment     = "production"
      DeploymentStage = local.deployment_stage
      CostCenter      = "platform-engineering"
    }
  )
}
