include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  root_config = read_terragrunt_config(find_in_parent_folders("root.hcl"))

  # Directly reference root locals - simplified
  hub         = local.root_config.locals.hub
  ack         = local.root_config.locals.ack
  spokes      = local.root_config.locals.spokes
  gitops      = local.root_config.locals.gitops
  addons      = local.root_config.locals.addons
  deployment  = local.root_config.locals.deployment
  paths       = local.root_config.locals.paths
  common_tags = local.root_config.locals.common_tags

  deployment_stage         = "staging"
  enable_cross_account_iam = false

  cluster_name = "${local.hub.cluster_name}-staging"
  vpc_name     = "${local.hub.vpc_name}-staging"

  repo_root   = get_repo_root()
  outputs_dir = "${local.repo_root}/${local.paths.outputs_dir}/staging"
}

terraform {
  source = "${get_repo_root()}/terraform//modules/root"
}

# Generate Kubernetes and Helm providers
generate "kube_providers" {
  path      = "kube_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "external" "cluster_exists" {
      program = ["bash", "-c", <<EOT
        cluster_names="${local.cluster_name}"
        %{if try(local.hub.old_cluster_name, "") != ""}
        cluster_names="$cluster_names ${local.hub.old_cluster_name}"
        %{endif}

        for cluster_name in $cluster_names; do
          if aws eks describe-cluster --name "$cluster_name" --region ${local.hub.aws_region} --profile ${local.hub.aws_profile} &>/dev/null; then
            echo "{\"cluster_name\":\"$cluster_name\",\"exists\":\"true\"}"
            exit 0
          fi
        done
        echo "{\"cluster_name\":\"${local.cluster_name}\",\"exists\":\"false\"}"
      EOT
      ]
    }

    locals {
      cluster_exists          = try(data.external.cluster_exists.result.exists, "false") == "true"
      active_cluster_name     = try(data.external.cluster_exists.result.cluster_name, "${local.cluster_name}")
      cluster_rename_in_progress = local.cluster_exists && local.active_cluster_name != "${local.cluster_name}"
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

      ack_services      = var.ack_services
      cluster_info      = local.cluster_info
      ack_hub_roles     = local.ack_hub_roles
      tags              = local.tags
      alias_tag         = "${spoke.alias}"
      spoke_alias       = "${spoke.alias}"
      deployment_stage  = var.deployment_stage

      enable_external_spoke = false
      enable_internal_spoke = true

      providers = {
        aws.hub   = aws.hub
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
  cluster_name       = local.cluster_name
  kubernetes_version = local.hub.kubernetes_version
  vpc_name           = local.vpc_name
  kubeconfig_dir     = local.deployment.kubeconfig_dir
  enable_argo        = try(local.hub.enable_argo, true)

  deployment_stage         = local.deployment_stage
  enable_cross_account_iam = local.enable_cross_account_iam
  argocd_chart_version     = local.deployment.argocd_chart_version

  ack_services = local.ack.controllers
  use_ack      = true

  spokes = [
    for spoke in local.spokes : {
      alias   = spoke.alias
      region  = spoke.region
      profile = spoke.profile
      tags    = merge(try(spoke.tags, {}), { Environment = "staging" })
    }
  ]

  addons = local.addons

  # GitOps configuration - simplified with separate repo URLs
  gitops_org_name        = local.gitops.org_name
  gitops_repo_name       = local.gitops.repo_name
  gitops_hub_repo_url    = local.gitops.hub_repo_url
  gitops_rgds_repo_url   = local.gitops.rgds_repo_url
  gitops_spokes_repo_url = local.gitops.spokes_repo_url
  gitops_branch          = local.gitops.branch
  gitops_bootstrap_path  = local.gitops.argo_bootstrap
  gitops_rgds_path       = local.gitops.argo_rgds
  gitops_spokes_path     = local.gitops.argo_spokes

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
