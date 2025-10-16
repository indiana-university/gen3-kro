###################################################################################################################################################
# Terragrunt Stack Configuration for gen3-kro Hub Cluster with Complete ACK Integration
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
  ack_services_config = {
    for service in local.ack_services : service => {
      namespace       = local.ack.namespace
      service_account = "${service}-ack-controller-sa"
    }
  }

  # GitOps URLs
  gitops_hub_repo_url = "https://${local.hub.gitops.github_url}/${local.hub.gitops.org_name}/${local.hub.gitops.repo_name}"

  # Common tags
  common_tags = {
    Project     = "gen3-kro"
    ManagedBy   = "Terragrunt"
    Owner       = "RDS"
  }
}

###################################################################################################################################################
# Provider Configuration - Hub Account
###################################################################################################################################################


# ###################################################################################################################################################
# # Provider Configuration - Spoke Accounts (one per spoke)
# ###################################################################################################################################################
# generate "providers_spokes" {
#   path      = "providers_spokes.tf"
#   if_exists = "overwrite_terragrunt"
#   contents  = <<-EOF
# %{~for spoke in local.spokes~}
#     provider "aws" {
#       alias   = "spoke_${spoke.alias}"
#       region  = "${spoke.region}"
#       profile = "${spoke.profile}"

#       default_tags {
#         tags = ${jsonencode(merge(local.common_tags, try(spoke.tags, {})))}
#       }
#     }
# %{~endfor~}
#   EOF
# }

###################################################################################################################################################
# VPC
###################################################################################################################################################
unit "vpc" {
  source = "git::git@github.com:indiana-university/gen3-kro.git//units/vpc?ref=${local.version}"
  path   = "vpc"
  values = {
    version = "jimi-ar"
    vpc_name           = "gen3-vpc"
    vpc_cidr           = "10.0.0.0/16"
    cluster_name       = "gen3-cluster"
    enable_nat_gateway = true
    single_nat_gateway = false
  }
}

# ACK IAM Policies - One unit per service
###################################################################################################################################################
# unit "ack_iam_policy_${service}" {
#   source = "git::git@github.com:indiana-university/gen3-kro.git//units/ack-iam-policy?ref=${local.version}"
#   path   = "ack_iam_policy_${service}"
#   values = {
#     create                 = true
#     service_name           = "${service}"
#     override_policy_path   = ""
#     override_policy_url    = ""
#     additional_policy_arns = {}
#   }
# }

# ###################################################################################################################################################
# # ACK Pod Identities - One unit per service (depends on ack_iam_policy)
# ###################################################################################################################################################
# %{~for service in local.ack_services~}
# unit "ack_pod_identity_${service}" {
#   source = "${local.units_path}/ack-pod-identity"

#   inputs = {
#     create       = true
#     cluster_name = local.hub.cluster_name
#     service_name = "${service}"

#     # Dependencies from ack_iam_policy
#     source_policy_documents   = dependency.unit.ack_iam_policy_${service}.outputs.source_policy_documents
#     override_policy_documents = dependency.unit.ack_iam_policy_${service}.outputs.override_policy_documents
#     policy_arns               = dependency.unit.ack_iam_policy_${service}.outputs.policy_arns
#     has_inline_policy         = dependency.unit.ack_iam_policy_${service}.outputs.has_inline_policy

#     # Association configuration
#     association_defaults = {
#       namespace = local.ack.namespace
#     }

#     associations = {
#       controller = {
#         cluster_name    = local.hub.cluster_name
#         service_account = "${service}-ack-controller-sa"
#       }
#     }

#     trust_policy_conditions = []
#     tags                   = local.common_tags
#   }
# }

# %{~endfor~}

# ###################################################################################################################################################
# # ACK Spoke Roles - One unit per service per spoke (depends on ack_iam_policy and ack_pod_identity)
# ###################################################################################################################################################
# %{~for spoke in local.spokes~}
# %{~for service in local.ack_services~}
# unit "ack_spoke_role_${spoke.alias}_${service}" {
#   source = "${local.units_path}/ack-spoke-role"

#   providers = {
#     aws.spoke = aws.spoke_${spoke.alias}
#   }

#   inputs = {
#     create       = ${spoke.enabled}
#     cluster_name = local.hub.cluster_name
#     service_name = "${service}"
#     spoke_alias  = "${spoke.alias}"

#     # Dependencies
#     hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_${service}.outputs.iam_role_arn
#     combined_policy_json      = dependency.unit.ack_iam_policy_${service}.outputs.combined_policy_json
#     policy_arns               = dependency.unit.ack_iam_policy_${service}.outputs.policy_arns
#     has_inline_policy         = dependency.unit.ack_iam_policy_${service}.outputs.has_inline_policy
#     has_managed_policy        = dependency.unit.ack_iam_policy_${service}.outputs.has_managed_policy

#     tags = merge(local.common_tags, try(${jsonencode(spoke.tags)}, {}))
#   }
# }

# %{~endfor~}
# %{~endfor~}

# ###################################################################################################################################################
# # Cross-Account Policies - One unit per service (depends on ack_pod_identity and ack_spoke_role)
# ###################################################################################################################################################
# %{~for service in local.ack_services~}
# unit "cross_account_policy_${service}" {
#   source = "${local.units_path}/cross-account-policy"

#   inputs = {
#     create       = true
#     service_name = "${service}"

#     # Dependencies
#     hub_pod_identity_role_arn = dependency.unit.ack_pod_identity_${service}.outputs.iam_role_arn

#     # Collect spoke role ARNs for this service from all enabled spokes
#     spoke_role_arns = [
# %{~for spoke in local.spokes~}
# %{~if spoke.enabled~}
#       dependency.unit.ack_spoke_role_${spoke.alias}_${service}.outputs.role_arn,
# %{~endif~}
# %{~endfor~}
#     ]

#     tags = local.common_tags
#   }
# }

# %{~endfor~}

# ###################################################################################################################################################
# # End of Stack Configuration
# ###################################################################################################################################################
