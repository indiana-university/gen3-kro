# root.hcl - Root Terragrunt configuration
# This file contains common configuration for all Terragrunt modules

locals {
  # Repository root
  repo_root = get_repo_root()
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region  = var.hub_aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      ManagedBy  = "Terragrunt"
      Repository = "gen3-kro"
      Blueprint  = "multi-account-eks-gitops"
    }
  }
}
EOF
}

# Generate Terraform version constraints
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

# Remote state configuration
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "gen3-kro-envs-4852"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true

    s3_bucket_tags = {
      Name       = "gen3-kro-terraform-state"
      ManagedBy  = "Terragrunt"
      Repository = "gen3-kro"
    }
  }
}

# Terraform configuration
terraform {
  # Common arguments for all Terraform commands
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

  # Before and after hooks
  before_hook "before_hook" {
    commands     = ["apply", "plan"]
    execute      = ["echo", "Running Terraform"]
  }
}
