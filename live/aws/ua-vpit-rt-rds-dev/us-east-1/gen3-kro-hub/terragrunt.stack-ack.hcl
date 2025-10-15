###################################################################################################################################################
# Terragrunt Stack Configuration for gen3-kro Hub Cluster with ACK Cross-Account Support
###################################################################################################################################################

locals {
  # Load stack configuration from config.yaml
  stack_config = yamldecode(file("config.yaml"))

  # Paths
  repo_root  = get_repo_root()
  units_path = "${local.repo_root}/units"

  # Extract configuration sections
  hub    = local.stack_config.hub
  ack    = local.stack_config.ack
  spokes = local.stack_config.spokes
  paths  = local.stack_config.paths

  # ACK Services configuration
  ack_services = toset(local.ack.controllers)

  # Common tags
  common_tags = {
    Project     = "gen3-kro"
    ManagedBy   = "Terragrunt"
    Environment = "production"
  }
}

###################################################################################################################################################
# Remote State Configuration
###################################################################################################################################################
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = local.paths.terraform_state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.hub.aws_region
    encrypt        = true
    dynamodb_table = local.paths.terraform_locks_table
  }
}

###################################################################################################################################################
# Provider Configuration - Hub Account
###################################################################################################################################################
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region  = "${local.hub.aws_region}"
      profile = "${local.hub.aws_profile}"

      default_tags {
        tags = ${jsonencode(local.common_tags)}
      }
    }
  EOF
}

###################################################################################################################################################
# Provider Configuration - Spoke Accounts
###################################################################################################################################################
generate "providers_spokes" {
  path      = "providers_spokes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    %{for spoke in local.spokes~}
    provider "aws" {
      alias   = "spoke_${spoke.alias}"
      region  = "${spoke.region}"
      profile = "${spoke.profile}"

      default_tags {
        tags = ${jsonencode(merge(local.common_tags, try(spoke.tags, {})))}
      }
    }
    %{endfor~}
  EOF
}

###################################################################################################################################################
# Units - ACK IAM Policies (one per service)
###################################################################################################################################################
%{for service in local.ack_services~}
unit "ack_iam_policy_${service}" {
  source = "${local.units_path}/ack-iam-policy"

  inputs = {
    create       = true
    service_name = "${service}"

    # Optional override policy path
    override_policy_path = ""

    # Additional managed policy ARNs if needed
    additional_policy_arns = {}
  }
}
%{endfor~}

###################################################################################################################################################
# Units - ACK Pod Identities (one per service)
###################################################################################################################################################
%{for service in local.ack_services~}
unit "ack_pod_identity_${service}" {
  source = "${local.units_path}/ack-pod-identity"

  inputs = {
    create       = true
    cluster_name = local.hub.cluster_name
    service_name = "${service}"

    # Policy inputs from ack-iam-policy
    source_policy_documents   = dependency.unit.ack_iam_policy_${service}.outputs.source_policy_documents
    override_policy_documents = dependency.unit.ack_iam_policy_${service}.outputs.override_policy_documents
    policy_arns               = dependency.unit.ack_iam_policy_${service}.outputs.policy_arns
    has_inline_policy         = dependency.unit.ack_iam_policy_${service}.outputs.has_inline_policy

    # Association configuration
    association_defaults = {
      namespace = local.ack.namespace
    }

    associations = {
      controller = {
        cluster_name    = local.hub.cluster_name
        service_account = "${service}-ack-controller-sa"
      }
    }

    trust_policy_conditions = []
    tags                   = local.common_tags
  }
}
%{endfor~}

###################################################################################################################################################
# Units - ACK Spoke Roles (one per service per spoke)
###################################################################################################################################################
%{for spoke in local.spokes~}
%{for service in local.ack_services~}
unit "ack_spoke_role_${spoke.alias}_${service}" {
  source = "${local.units_path}/ack-spoke-role"

  providers = {
    aws.spoke = aws.spoke_${spoke.alias}
  }

  inputs = {
    create       = ${spoke.enabled}
    cluster_name = local.hub.cluster_name
    service_name = "${service}"
    spoke_alias  = "${spoke.alias}"

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_${service}.outputs.iam_role_arn

    # Policy inputs from ack-iam-policy
    combined_policy_json = dependency.unit.ack_iam_policy_${service}.outputs.combined_policy_json
    policy_arns          = dependency.unit.ack_iam_policy_${service}.outputs.policy_arns
    has_inline_policy    = dependency.unit.ack_iam_policy_${service}.outputs.has_inline_policy
    has_managed_policy   = dependency.unit.ack_iam_policy_${service}.outputs.has_managed_policy

    tags = merge(local.common_tags, try(${spoke.alias}.tags, {}))
  }
}
%{endfor~}
%{endfor~}

###################################################################################################################################################
# Units - Cross-Account Policies (one per service)
###################################################################################################################################################
%{for service in local.ack_services~}
unit "cross_account_policy_${service}" {
  source = "${local.units_path}/cross-account-policy"

  inputs = {
    create       = true
    service_name = "${service}"

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_${service}.outputs.iam_role_arn

    # Collect spoke role ARNs for this service
    spoke_role_arns = [
      %{for spoke in local.spokes~}
      %{if spoke.enabled~}
      dependency.unit.ack_spoke_role_${spoke.alias}_${service}.outputs.role_arn,
      %{endif~}
      %{endfor~}
    ]

    tags = local.common_tags
  }
}
%{endfor~}

###################################################################################################################################################
# End of Stack Configuration
###################################################################################################################################################
