locals {
  repo_root = get_repo_root()

  # Simplified environment detection
  environment = coalesce(
    get_env("ENVIRONMENT", ""),
    get_env("ENV", ""),
    get_env("TERRAGRUNT_ENV", ""),
    try(split("/", path_relative_to_include())[0], "")
  )

  # Load configurations - simplified without conditional
  base_config = yamldecode(file("${local.repo_root}/config/base.yaml"))
  env_config  = yamldecode(file("${local.repo_root}/config/environments/${local.environment}.yaml"))

  # Simplified config merging - single pass
  hub        = merge(lookup(local.base_config, "hub", {}), lookup(local.env_config, "hub", {}))
  ack        = merge(lookup(local.base_config, "ack", {}), lookup(local.env_config, "ack", {}))
  spokes     = lookup(local.env_config, "spokes", lookup(local.base_config, "spokes", []))
  paths      = merge(lookup(local.base_config, "paths", {}), lookup(local.env_config, "paths", {}))
  deployment = merge(lookup(local.base_config, "deployment", {}), lookup(local.env_config, "deployment", {}))
  addons     = merge(lookup(local.base_config, "addons", {}), lookup(local.env_config, "addons", {}))

  # Simplified gitops merge - cleaner nested merge
  base_gitops = lookup(local.base_config, "gitops", {})
  env_gitops  = lookup(local.env_config, "gitops", {})

  gitops = merge(
    local.base_gitops,
    local.env_gitops,
    {
      addons   = merge(lookup(local.base_gitops, "addons", {}), lookup(local.env_gitops, "addons", {}))
      fleet    = merge(lookup(local.base_gitops, "fleet", {}), lookup(local.env_gitops, "fleet", {}))
      platform = merge(lookup(local.base_gitops, "platform", {}), lookup(local.env_gitops, "platform", {}))
      workload = merge(lookup(local.base_gitops, "workload", {}), lookup(local.env_gitops, "workload", {}))
    }
  )

  # Common tags
  common_tags = {
    ManagedBy   = "Terragrunt"
    Repository  = "gen3-kro"
    Blueprint   = "multi-account-eks-gitops"
    Owner       = "platform-engineering"
    Environment = local.environment
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
        Name        = "gen3-kro-terraform-state"
        Purpose     = "Terraform state storage"
        Environment = "shared"
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
