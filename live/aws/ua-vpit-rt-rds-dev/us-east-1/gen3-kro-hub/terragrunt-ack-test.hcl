###################################################################################################################################################
# ACK Cross-Account Stack Configuration Test
# This file tests the ACK modules with config.yaml
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

  # ACK Services - limit to first 2 for testing
  ack_services_test = ["ec2", "iam"]
  
  # First spoke for testing
  test_spoke = local.spokes[0]
  
  # Common tags
  common_tags = {
    Project     = "gen3-kro"
    ManagedBy   = "Terragrunt"
    Environment = "test"
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
    key            = "ack-test/${path_relative_to_include()}/terraform.tfstate"
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
# Provider Configuration - Spoke Account
###################################################################################################################################################
generate "provider_spoke" {
  path      = "provider_spoke.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias   = "spoke_${local.test_spoke.alias}"
      region  = "${local.test_spoke.region}"
      profile = "${local.test_spoke.profile}"

      default_tags {
        tags = ${jsonencode(merge(local.common_tags, try(local.test_spoke.tags, {})))}
      }
    }
  EOF
}

###################################################################################################################################################
# Units - EC2 ACK Service
###################################################################################################################################################

# Unit 1: ACK IAM Policy for EC2
unit "ack_iam_policy_ec2" {
  source = "${local.units_path}/ack-iam-policy"

  inputs = {
    create                 = true
    service_name           = "ec2"
    override_policy_path   = ""
    override_policy_url    = ""
    additional_policy_arns = {}
  }
}

# Unit 2: ACK Pod Identity for EC2
unit "ack_pod_identity_ec2" {
  source = "${local.units_path}/ack-pod-identity"

  inputs = {
    create       = true
    cluster_name = local.hub.cluster_name
    service_name = "ec2"
    
    # Dependencies from ack_iam_policy_ec2
    source_policy_documents   = dependency.unit.ack_iam_policy_ec2.outputs.source_policy_documents
    override_policy_documents = dependency.unit.ack_iam_policy_ec2.outputs.override_policy_documents
    policy_arns               = dependency.unit.ack_iam_policy_ec2.outputs.policy_arns
    has_inline_policy         = dependency.unit.ack_iam_policy_ec2.outputs.has_inline_policy
    
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
    
    trust_policy_conditions = []
    tags                   = local.common_tags
  }
}

# Unit 3: ACK Spoke Role for EC2 in spoke1
unit "ack_spoke_role_spoke1_ec2" {
  source = "${local.units_path}/ack-spoke-role"

  providers = {
    aws.spoke = aws.spoke_${local.test_spoke.alias}
  }

  inputs = {
    create       = local.test_spoke.enabled
    cluster_name = local.hub.cluster_name
    service_name = "ec2"
    spoke_alias  = local.test_spoke.alias
    
    # Dependencies
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_ec2.outputs.iam_role_arn
    combined_policy_json      = dependency.unit.ack_iam_policy_ec2.outputs.combined_policy_json
    policy_arns               = dependency.unit.ack_iam_policy_ec2.outputs.policy_arns
    has_inline_policy         = dependency.unit.ack_iam_policy_ec2.outputs.has_inline_policy
    has_managed_policy        = dependency.unit.ack_iam_policy_ec2.outputs.has_managed_policy
    
    tags = merge(local.common_tags, try(local.test_spoke.tags, {}))
  }
}

# Unit 4: Cross-Account Policy for EC2
unit "cross_account_policy_ec2" {
  source = "${local.units_path}/cross-account-policy"

  inputs = {
    create       = true
    service_name = "ec2"
    
    # Dependencies
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_ec2.outputs.iam_role_arn
    
    # Spoke role ARNs
    spoke_role_arns = [
      dependency.unit.ack_spoke_role_spoke1_ec2.outputs.role_arn
    ]
    
    tags = local.common_tags
  }
}

###################################################################################################################################################
# Units - IAM ACK Service
###################################################################################################################################################

# Unit 5: ACK IAM Policy for IAM
unit "ack_iam_policy_iam" {
  source = "${local.units_path}/ack-iam-policy"

  inputs = {
    create                 = true
    service_name           = "iam"
    override_policy_path   = ""
    override_policy_url    = ""
    additional_policy_arns = {}
  }
}

# Unit 6: ACK Pod Identity for IAM
unit "ack_pod_identity_iam" {
  source = "${local.units_path}/ack-pod-identity"

  inputs = {
    create       = true
    cluster_name = local.hub.cluster_name
    service_name = "iam"
    
    # Dependencies from ack_iam_policy_iam
    source_policy_documents   = dependency.unit.ack_iam_policy_iam.outputs.source_policy_documents
    override_policy_documents = dependency.unit.ack_iam_policy_iam.outputs.override_policy_documents
    policy_arns               = dependency.unit.ack_iam_policy_iam.outputs.policy_arns
    has_inline_policy         = dependency.unit.ack_iam_policy_iam.outputs.has_inline_policy
    
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
    
    trust_policy_conditions = []
    tags                   = local.common_tags
  }
}

# Unit 7: ACK Spoke Role for IAM in spoke1
unit "ack_spoke_role_spoke1_iam" {
  source = "${local.units_path}/ack-spoke-role"

  providers = {
    aws.spoke = aws.spoke_${local.test_spoke.alias}
  }

  inputs = {
    create       = local.test_spoke.enabled
    cluster_name = local.hub.cluster_name
    service_name = "iam"
    spoke_alias  = local.test_spoke.alias
    
    # Dependencies
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_iam.outputs.iam_role_arn
    combined_policy_json      = dependency.unit.ack_iam_policy_iam.outputs.combined_policy_json
    policy_arns               = dependency.unit.ack_iam_policy_iam.outputs.policy_arns
    has_inline_policy         = dependency.unit.ack_iam_policy_iam.outputs.has_inline_policy
    has_managed_policy        = dependency.unit.ack_iam_policy_iam.outputs.has_managed_policy
    
    tags = merge(local.common_tags, try(local.test_spoke.tags, {}))
  }
}

# Unit 8: Cross-Account Policy for IAM
unit "cross_account_policy_iam" {
  source = "${local.units_path}/cross-account-policy"

  inputs = {
    create       = true
    service_name = "iam"
    
    # Dependencies
    hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_iam.outputs.iam_role_arn
    
    # Spoke role ARNs
    spoke_role_arns = [
      dependency.unit.ack_spoke_role_spoke1_iam.outputs.role_arn
    ]
    
    tags = local.common_tags
  }
}

###################################################################################################################################################
# End of Stack Configuration
###################################################################################################################################################
