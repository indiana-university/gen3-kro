# Root Terragrunt configuration for catalog units
# This file is referenced by units in catalog/units/*

# Remote state configuration
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket  = "gen3-kro-envs-4852"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# Locals available to all units
locals {
  # Repository root path
  repo_root = get_repo_root()

  # Common tags - can be overridden by stack inputs
  common_tags = {
    Project     = "gen3-kro"
    ManagedBy   = "Terragrunt"
  }
}

# Terraform version constraints
terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()
  }
}
