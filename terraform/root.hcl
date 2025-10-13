locals {
  repo_root = get_repo_root()

  # Load configuration from single base config file
  base_config = yamldecode(file("${local.repo_root}/config/base.yaml"))

  # Direct config references - no environment-specific overrides
  hub        = lookup(local.base_config, "hub", {})
  ack        = lookup(local.base_config, "ack", {})
  spokes     = lookup(local.base_config, "spokes", [])
  paths      = lookup(local.base_config, "paths", {})
  deployment = lookup(local.base_config, "deployment", {})
  addons     = lookup(local.base_config, "addons", {})
  gitops     = lookup(local.base_config, "gitops", {})

  # Common tags - no deployment stage
  common_tags = {
    ManagedBy  = "Terragrunt"
    Repository = "gen3-kro"
    Blueprint  = "multi-account-eks-gitops"
    Owner      = "platform-engineering"
  }
}

remote_state {
  backend = "s3"
  config = {
    bucket  = local.paths.terraform_state_bucket
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = local.hub.aws_region
    encrypt = true

    s3_bucket_tags = merge(
      local.common_tags,
      {
        Name    = "gen3-kro-envs-4852"
        Purpose = "Terraform state storage"
      }
    )
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias   = "hub"
      profile = "${local.hub.aws_profile}"
      region  = "${local.hub.aws_region}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }

    %{for spoke in local.spokes~}
    provider "aws" {
      alias   = "${spoke.alias}"
      profile = "${spoke.profile}"
      region  = "${spoke.region}"

      default_tags {
        tags = ${jsonencode(merge(local.common_tags, spoke.tags))}
      }
    }
    %{endfor~}
  EOF
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5.0, < 2.0.0"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
          configuration_aliases = [
            aws.hub,
            %{for spoke in local.spokes~}
            aws.${spoke.alias},
            %{endfor~}
          ]
        }

        external = {
          source  = "hashicorp/external"
          version = "~> 2.3"
        }

        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.23"
        }

        helm = {
          source  = "hashicorp/helm"
          version = ">= 3.0.2"
        }

        kubectl = {
          source  = "gavinbunney/kubectl"
          version = "~> 1.14"
        }
      }
    }
  EOF
}

terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }

  extra_arguments "auto_format" {
    commands  = ["plan", "apply"]
    arguments = ["-compact-warnings"]
  }

  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=20m"]
  }

  extra_arguments "debug" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      TF_LOG = get_env("TF_LOG", "")
    }
  }
}

inputs = {
  hub_config        = local.hub
  ack_config        = local.ack
  spokes_config     = local.spokes
  gitops_config     = local.gitops
  deployment_config = local.deployment
  addons_config     = local.addons
  common_tags       = local.common_tags
}
