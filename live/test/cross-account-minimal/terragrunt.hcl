###################################################################################################################################################
# Test Stack - Minimal Cross-Account Policy Deployment
# This tests the cross-account-policy module with minimal dependencies
###################################################################################################################################################

locals {
  # Load configuration
  config = yamldecode(file("config.yaml"))

  # Extract sections
  hub    = local.config.hub
  ack    = local.config.ack
  spokes = local.config.spokes

  # Repository root
  repo_root  = get_repo_root()
  units_path = "${local.repo_root}/units"

  # ACK services to test
  ack_services = toset(local.ack.controllers)

  # Common tags
  common_tags = merge(
    local.config.tags,
    {
      Stack = "test-cross-account-minimal"
    }
  )
}

###################################################################################################################################################
# Provider Configuration
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
# Backend Configuration
###################################################################################################################################################
remote_state {
  backend = "local"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

###################################################################################################################################################
# Units Configuration
###################################################################################################################################################

# Unit 1: ACK IAM Policy (for each service)
unit "ack_iam_policy_ec2" {
  source = "${local.units_path}/ack-iam-policy"

  inputs = {
    create       = true
    service_name = "ec2"
  }
}

unit "ack_iam_policy_iam" {
  source = "${local.units_path}/ack-iam-policy"

  inputs = {
    create       = true
    service_name = "iam"
  }
}

# Unit 2: ACK Pod Identity (for each service) - depends on IAM policy
unit "ack_pod_identity_ec2" {
  source = "${local.units_path}/ack-pod-identity"

  depends_on = [unit.ack_iam_policy_ec2]

  inputs = {
    create       = true
    cluster_name = local.hub.cluster_name
    service_name = "ec2"

    # Policy inputs from ack-iam-policy
    source_policy_documents   = unit.ack_iam_policy_ec2.outputs.source_policy_documents
    override_policy_documents = unit.ack_iam_policy_ec2.outputs.override_policy_documents
    policy_arns               = unit.ack_iam_policy_ec2.outputs.policy_arns
    has_inline_policy         = unit.ack_iam_policy_ec2.outputs.has_inline_policy

    # Association configuration
    association_defaults = {
      namespace = local.ack.namespace
    }

    associations = {
      controller = {
        cluster_name    = local.hub.cluster_name
        service_account = "ec2-ack-controller-sa"
      }
    }

    tags = local.common_tags
  }
}

unit "ack_pod_identity_iam" {
  source = "${local.units_path}/ack-pod-identity"

  depends_on = [unit.ack_iam_policy_iam]

  inputs = {
    create       = true
    cluster_name = local.hub.cluster_name
    service_name = "iam"

    # Policy inputs from ack-iam-policy
    source_policy_documents   = unit.ack_iam_policy_iam.outputs.source_policy_documents
    override_policy_documents = unit.ack_iam_policy_iam.outputs.override_policy_documents
    policy_arns               = unit.ack_iam_policy_iam.outputs.policy_arns
    has_inline_policy         = unit.ack_iam_policy_iam.outputs.has_inline_policy

    # Association configuration
    association_defaults = {
      namespace = local.ack.namespace
    }

    associations = {
      controller = {
        cluster_name    = local.hub.cluster_name
        service_account = "iam-ack-controller-sa"
      }
    }

    tags = local.common_tags
  }
}

# Unit 3: Cross-Account Policy (for each service) - depends on pod identity
unit "cross_account_policy_ec2" {
  source = "${local.units_path}/cross-account-policy"

  depends_on = [unit.ack_pod_identity_ec2]

  inputs = {
    create       = true
    service_name = "ec2"

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = unit.ack_pod_identity_ec2.outputs.iam_role_arn

    # Build spoke role ARNs
    spoke_role_arns = [
      for spoke in local.spokes :
      "arn:aws:iam::${spoke.account_id}:role/${spoke.alias}-ack-ec2-spoke-role"
    ]

    tags = local.common_tags
  }
}

unit "cross_account_policy_iam" {
  source = "${local.units_path}/cross-account-policy"

  depends_on = [unit.ack_pod_identity_iam]

  inputs = {
    create       = true
    service_name = "iam"

    # Hub pod identity role ARN
    hub_pod_identity_role_arn = unit.ack_pod_identity_iam.outputs.iam_role_arn

    # Build spoke role ARNs
    spoke_role_arns = [
      for spoke in local.spokes :
      "arn:aws:iam::${spoke.account_id}:role/${spoke.alias}-ack-iam-spoke-role"
    ]

    tags = local.common_tags
  }
}

###################################################################################################################################################
# Outputs
###################################################################################################################################################
inputs = {
  # EC2 outputs
  ec2_hub_role_arn           = unit.ack_pod_identity_ec2.outputs.iam_role_arn
  ec2_cross_account_policy   = unit.cross_account_policy_ec2.outputs.policy_name
  ec2_spoke_role_arns        = unit.cross_account_policy_ec2.outputs.spoke_role_arns

  # IAM outputs
  iam_hub_role_arn           = unit.ack_pod_identity_iam.outputs.iam_role_arn
  iam_cross_account_policy   = unit.cross_account_policy_iam.outputs.policy_name
  iam_spoke_role_arns        = unit.cross_account_policy_iam.outputs.spoke_role_arns
}
