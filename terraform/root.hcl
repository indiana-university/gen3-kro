# terraform/terragrunt.hcl
# Root-level Terragrunt configuration for gen3-kro
# This file provides shared configuration for all environments

locals {
  # Load centralized configuration from YAML
  config_file = "${get_repo_root()}/terraform/config.yaml"
  config      = yamldecode(file(local.config_file))

  # Extract configuration sections for easy access
  hub        = local.config.hub
  ack        = local.config.ack
  spokes     = local.config.spokes
  gitops     = local.config.gitops
  paths      = local.config.paths
  deployment = local.config.deployment
  addons     = local.config.addons

  # Common tags applied to all resources
  common_tags = {
    ManagedBy  = "Terragrunt"
    Repository = "gen3-kro"
    Blueprint  = "multi-account-eks-gitops"
    Owner      = "platform-engineering"
  }
}

# Remote state configuration - S3 backend WITHOUT DynamoDB locking
# NOTE: No DynamoDB table to prevent lock issues
remote_state {
  backend = "s3"

  config = {
    bucket  = local.paths.terraform_state_bucket
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = local.hub.aws_region
    encrypt = true

    # NO dynamodb_table - lock corruption risk if processes are killed
    # Always wait for terraform commands to complete or timeout naturally

    # Tags for S3 bucket
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

# Generate provider configuration dynamically from config.yaml
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    # Hub AWS provider
    provider "aws" {
      alias   = "hub"
      profile = "${local.hub.aws_profile}"
      region  = "${local.hub.aws_region}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }

    # Spoke AWS providers - generated dynamically from config.yaml
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

# Generate versions configuration with required provider versions
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

# Terraform configuration
terraform {
  # Always include all variable files
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }

  # Auto-format and compact warnings
  extra_arguments "auto_format" {
    commands  = ["plan", "apply"]
    arguments = ["-compact-warnings"]
  }

  # Retry on lock timeout
  extra_arguments "retry_lock" {
    commands  = get_terraform_commands_that_need_locking()
    arguments = ["-lock-timeout=20m"]
  }

  # Enable detailed logging in debug mode
  extra_arguments "debug" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      TF_LOG = get_env("TF_LOG", "")
    }
  }
}

# Inputs available to all child configurations
inputs = {
  # Configuration sections
  hub_config        = local.hub
  ack_config        = local.ack
  spokes_config     = local.spokes
  gitops_config     = local.gitops
  deployment_config = local.deployment
  addons_config     = local.addons

  # Common tags
  common_tags = local.common_tags
}
