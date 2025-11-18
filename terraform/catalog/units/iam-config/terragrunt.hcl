###############################################################################
# IAM Configuration Unit Terragrunt Configuration
#
# This unit creates:
# 1. CSOC pod identity roles (for controllers running in CSOC cluster)
# 2. Cross-account policies (allowing CSOC pods to assume spoke roles)
# 3. Spoke IAM roles (for spoke account resources)
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}"
}
###############################################################################
# Dependencies
###############################################################################
dependency "csoc" {
  config_path = "../k8s-cluster"

  # Allow mocks during plan to show IAM resources
  # During apply, require real outputs (mocks disabled)
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    # Provide realistic mock values for plan phase
    # These allow IAM resources to show in plan even before cluster exists
    cluster_name        = values.cluster_name
    cluster_id          = "mock-cluster-id-for-plan"
    cluster_arn         = "arn:aws:eks:${values.region}:123456789012:cluster/${values.cluster_name}"
    oidc_provider       = "oidc.eks.${values.region}.amazonaws.com/id/MOCK123456789ABCDEF"
    oidc_provider_arn   = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.${values.region}.amazonaws.com/id/MOCK123456789ABCDEF"
    oidc_issuer_url     = "https://oidc.eks.${values.region}.amazonaws.com/id/MOCK123456789ABCDEF"
  }
}

###############################################################################
# Inputs
###############################################################################
inputs = merge(
  {
    csoc_provider = values.csoc_provider
    tags          = values.tags
    cluster_name  = values.cluster_name

    # IAM policies (loaded from repository files)
    csoc_iam_policies  = values.csoc_iam_policies
    spoke_iam_policies = values.spoke_iam_policies

    # Controller configurations - unified map of all controllers (addons, ACK, ASO, GCC)
    addon_configs = values.all_configs

    # IAM creation flag based on k8s cluster existence. if cluster is manually deleted, IAM resources would be cleaned up on next apply.
    enable_k8s_cluster = values.enable_k8s_cluster && (
      values.csoc_provider == "aws" ? (
        # AWS: Check if cluster_arn is real (not mock)
        try(dependency.csoc.outputs.cluster_arn, null) != null &&
        try(dependency.csoc.outputs.cluster_arn, "") != ""
      ) : values.csoc_provider == "azure" ? (
        # Azure: Check if cluster_id is real
        try(dependency.csoc.outputs.cluster_id, null) != null &&
        try(dependency.csoc.outputs.cluster_id, "") != ""
      ) : (
        # GCP: Check if cluster_id is real
        try(dependency.csoc.outputs.cluster_id, null) != null &&
        try(dependency.csoc.outputs.cluster_id, "") != ""
      )
    )

    # Provider-specific configuration
    csoc_profile_name   = values.profile
    csoc_region         = values.region
    csoc_subscription_id = values.subscription_id
    csoc_project_id     = values.project_id

    # Spokes configuration
    spokes = values.spokes

    # IAM policy sources (track which folder was used)
    csoc_iam_policy_sources  = values.csoc_iam_policy_sources
    spoke_iam_policy_sources = values.spoke_iam_policy_sources
  },
  # Dynamically add spoke provider variables
  {
    for spoke_config in values.spokes_config :
    "${spoke_config.alias}_profile" => lookup(lookup(spoke_config, "provider", {}), "aws_profile", "")
    if lookup(spoke_config, "enabled", false)
  },
  {
    for spoke_config in values.spokes_config :
    "${spoke_config.alias}_region" => lookup(lookup(spoke_config, "provider", {}), "aws_region", "")
    if lookup(spoke_config, "enabled", false)
  },
  {
    for spoke_config in values.spokes_config :
    "${spoke_config.alias}_subscription_id" => lookup(lookup(spoke_config, "provider", {}), "azure_subscription_id", "")
    if lookup(spoke_config, "enabled", false)
  },
  {
    for spoke_config in values.spokes_config :
    "${spoke_config.alias}_project_id" => lookup(lookup(spoke_config, "provider", {}), "gcp_project_id", "")
    if lookup(spoke_config, "enabled", false)
  }
)

###############################################################################
# Backend Configuration
###############################################################################
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<EOF
terraform {
  backend "s3" {
    bucket  = "${values.state_bucket}"
    key     = "${values.csoc_alias}/units/iam-config/terraform.tfstate"
    region  = "${values.region}"
    encrypt = true
${values.state_locks_table != "" ? "    dynamodb_table = \"${values.state_locks_table}\"" : ""}
  }
}
EOF
    : values.csoc_provider == "azure" ? <<EOF
terraform {
  backend "azurerm" {
    storage_account_name = "${values.state_storage_account}"
    container_name       = "${values.state_container}"
    key                  = "${values.csoc_alias}/units/iam-config/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/iam-config"
  }
}
EOF
    : ""
  )
}

###############################################################################
# Generate Provider Configurations
###############################################################################
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
################################################################################
# CSOC Provider Configuration - AWS
################################################################################
provider "aws" {
  alias   = "csoc"
  profile = var.csoc_profile_name
  region  = var.csoc_region
}

%{for spoke_config in values.spokes_config~}
# Provider for ${spoke_config.alias}
provider "aws" {
  alias   = "${spoke_config.alias}"
  profile = var.${spoke_config.alias}_profile
  region  = var.${spoke_config.alias}_region
}
%{endfor~}
EOF
    : values.csoc_provider == "azure" ? <<-EOF

################################################################################
# CSOC Provider Configuration - Azure
################################################################################
provider "azurerm" {
  alias           = "csoc"
  subscription_id = var.csoc_subscription_id
  features {}
}
%{for spoke_config in values.spokes_config~}
# Provider for ${spoke_config.alias}
provider "azurerm" {
  alias           = "${spoke_config.alias}"
  subscription_id = var.${spoke_config.alias}_subscription_id
  features {}
}
%{endfor~}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
################################################################################
# CSOC Provider Configuration - GCP
################################################################################
provider "google" {
  alias   = "csoc"
  project = var.csoc_project_id
  region  = var.csoc_region
}


%{for spoke_config in values.spokes_config~}
# Provider for ${spoke_config.alias}
provider "google" {
  alias   = "${spoke_config.alias}"
  project = var.${spoke_config.alias}_project_id
  region  = var.${spoke_config.alias}_region
}
%{endfor~}
EOF
    : ""
  )
}

###############################################################################
# Generate CSOC Account Data Sources
###############################################################################
generate "csoc_data_sources" {
  path      = "data_sources.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
# CSOC Account Data Source
data "aws_caller_identity" "csoc" {
  provider = aws.csoc
}

# Spoke Account Data Sources (for cross-account comparison)
%{for spoke_config in values.spokes_config~}
data "aws_caller_identity" "${spoke_config.alias}" {
  provider = aws.${spoke_config.alias}
}
%{endfor~}
EOF
    : values.csoc_provider == "azure" ? <<-EOF
# CSOC Azure Data Sources
data "azurerm_client_config" "csoc" {
  provider = azurerm.csoc
}

# Spoke Subscription Data Sources (for cross-subscription comparison)
%{for spoke_config in values.spokes_config~}
data "azurerm_client_config" "${spoke_config.alias}" {
  provider = azurerm.${spoke_config.alias}
}
%{endfor~}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
# CSOC GCP Data Sources
data "google_client_config" "csoc" {
  provider = google.csoc
}

data "google_project" "csoc" {
  provider   = google.csoc
  project_id = var.csoc_project_id
}

# Spoke Project Data Sources (for cross-project comparison)
%{for spoke_config in values.spokes_config~}
data "google_project" "${spoke_config.alias}" {
  provider   = google.${spoke_config.alias}
  project_id = var.${spoke_config.alias}_project_id
}
%{endfor~}
EOF
    : ""
  )
}

###############################################################################
# Generate CSOC IAM Policies (for pod identities)
###############################################################################
generate "csoc_policies" {
  path      = "csoc_policies.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# CSOC IAM Policies - For Pod/Managed/Workload Identity Roles
###############################################################################

%{for service_name, policy_json in values.csoc_iam_policies~}
module "csoc-policy-${service_name}" {
  source = "./iam-policy"

  service_name       = "${service_name}"
  policy_inline_json = ${jsonencode(policy_json)}

  %{if values.csoc_provider == "aws"~}
  account_id      = data.aws_caller_identity.csoc.account_id
  csoc_account_id = data.aws_caller_identity.csoc.account_id
  %{endif~}
  %{if values.csoc_provider == "azure"~}
  role_definition_json = ${jsonencode(policy_json)}
  subscription_id      = data.azurerm_client_config.csoc.subscription_id
  tenant_id            = data.azurerm_client_config.csoc.tenant_id
  %{endif~}
  %{if values.csoc_provider == "gcp"~}
  role_definition_yaml = ${jsonencode(policy_json)}
  project_id           = data.google_project.csoc.project_id
  project_number       = data.google_project.csoc.number
  %{endif~}
  policy_source = lookup(var.csoc_iam_policy_sources, "${service_name}", "_default")
}
%{endfor~}
EOF
}

###############################################################################
# Generate CSOC Pod Identity Roles
###############################################################################
generate "csoc_pod_identities" {
  path      = "csoc_pod_identities.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# CSOC Pod/Managed/Workload Identities - All Controllers running in CSOC cluster
###############################################################################

%{for service_name, service_config in values.all_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "pod-identity-${service_name}" {
  source = %{if values.csoc_provider == "aws"~}"./aws-pod-identity"%{else}%{if values.csoc_provider == "azure"~}"./azure-managed-identity"%{else}"./gcp-workload-identity"%{endif~}%{endif}

  create       = var.enable_k8s_cluster
  cluster_name = var.cluster_name
  context      = "csoc"

  service_name    = "${service_name}"
  namespace       = "${service_config.namespace}"
  service_account = "${service_config.service_account}"

  # Provider-specific policy fields
  %{if values.csoc_provider == "aws"~}
  loaded_inline_policy_document = try(module.csoc-policy-${service_name}.inline_policy_document, "")
  has_loaded_inline_policy      = try(module.csoc-policy-${service_name}.has_inline_policy, false)
  %{endif~}
  %{if values.csoc_provider == "azure"~}
  role_definition_json = try(module.csoc-policy-${service_name}.role_definition_json, "")
  has_role_definition  = try(module.csoc-policy-${service_name}.has_role_definition, false)
  %{endif~}
  %{if values.csoc_provider == "gcp"~}
  role_definition_yaml = try(module.csoc-policy-${service_name}.role_definition_yaml, "")
  has_role_definition  = try(module.csoc-policy-${service_name}.has_role_definition, false)
  %{endif~}

  tags = merge(
    var.tags,
    {
      service_name = "${service_name}"
      context      = "csoc"
    }
  )

  depends_on = [module.csoc-policy-${service_name}]
}
%{endif~}
%{endfor~}
EOF
}

###############################################################################
# Generate Spoke IAM Policies
###############################################################################
generate "spoke_policies" {
  path      = "spoke_policies.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# Spoke IAM Policies - For Spoke Roles/Identities/Service Accounts
###############################################################################

%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
# Policies for ${spoke_config.alias}
%{for service_name, policy_json in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke-policy-${spoke_config.alias}-${service_name}" {
  source = "./iam-policy"

  service_name       = "${service_name}"
  policy_inline_json = ${jsonencode(policy_json)}

  %{if values.csoc_provider == "aws"~}
  account_id      = data.aws_caller_identity.${spoke_config.alias}.account_id
  csoc_account_id = data.aws_caller_identity.csoc.account_id
  %{endif~}
  %{if values.csoc_provider == "azure"~}
  role_definition_json = ${jsonencode(policy_json)}
  subscription_id      = data.azurerm_client_config.${spoke_config.alias}.subscription_id
  tenant_id            = data.azurerm_client_config.${spoke_config.alias}.tenant_id
  %{endif~}
  %{if values.csoc_provider == "gcp"~}
  role_definition_yaml = ${jsonencode(policy_json)}
  project_id           = data.google_project.${spoke_config.alias}.project_id
  project_number       = data.google_project.${spoke_config.alias}.number
  %{endif~}
  policy_source = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "_default")
}
%{endfor~}

%{endif~}
%{endfor~}
EOF
}

###############################################################################
# Generate Spoke IAM Roles
###############################################################################
generate "spoke_roles" {
  path      = "spoke_roles.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# Spoke IAM Roles/Identities/Service Accounts - Trusted by CSOC Identities
###############################################################################

%{for spoke_config in values.spokes_config~}
# Roles/Identities for ${spoke_config.alias}
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke-role-${spoke_config.alias}-${service_name}" {
  source = %{if values.csoc_provider == "aws"~}"./aws-spoke-role"%{else}%{if values.csoc_provider == "azure"~}"./azure-spoke-role"%{else}"./gcp-spoke-role"%{endif~}%{endif}

  providers = {
    %{if values.csoc_provider == "aws"~}
    aws = aws.${spoke_config.alias}
    %{endif~}
    %{if values.csoc_provider == "azure"~}
    azurerm = azurerm.${spoke_config.alias}
    %{endif~}
    %{if values.csoc_provider == "gcp"~}
    google = google.${spoke_config.alias}
    %{endif~}
  }

  # Skip creation if spoke account/subscription/project == csoc (same account scenario)
  # In that case, we'll use the csoc identity directly via override_id
  create = ${lookup(spoke_config, "enabled", false)} && var.enable_k8s_cluster && ${lookup(lookup(values.all_configs, service_name, {}), "enable_identity", false)} && (%{if values.csoc_provider == "aws"~}data.aws_caller_identity.${spoke_config.alias}.account_id != data.aws_caller_identity.csoc.account_id%{else}%{if values.csoc_provider == "azure"~}data.azurerm_client_config.${spoke_config.alias}.subscription_id != data.azurerm_client_config.csoc.subscription_id%{else}data.google_project.${spoke_config.alias}.project_id != data.google_project.csoc.project_id%{endif~}%{endif})

  override_id = %{if values.csoc_provider == "aws"~}data.aws_caller_identity.${spoke_config.alias}.account_id == data.aws_caller_identity.csoc.account_id%{else}%{if values.csoc_provider == "azure"~}data.azurerm_client_config.${spoke_config.alias}.subscription_id == data.azurerm_client_config.csoc.subscription_id%{else}data.google_project.${spoke_config.alias}.project_id == data.google_project.csoc.project_id%{endif~}%{endif} ? (%{if contains(keys(values.all_configs), service_name) && lookup(lookup(values.all_configs, service_name, {}), "enable_identity", false)~}%{if values.csoc_provider == "aws"~}module.pod-identity-${service_name}.role_arn%{else}%{if values.csoc_provider == "azure"~}module.pod-identity-${service_name}.identity_id%{else}module.pod-identity-${service_name}.service_account_email%{endif~}%{endif~}%{else~}""%{endif~}) : null

  cluster_name = var.cluster_name
  service_name = "${service_name}"
  spoke_alias  = "${spoke_config.alias}"

  # Provider-specific CSOC identity references
  %{if values.csoc_provider == "aws"~}
  csoc_pod_identity_role_arn = %{if contains(keys(values.all_configs), service_name) && lookup(lookup(values.all_configs, service_name, {}), "enable_identity", false)~}module.pod-identity-${service_name}.role_arn%{else~}""%{endif}
  combined_policy_json       = try(module.spoke-policy-${spoke_config.alias}-${service_name}.inline_policy_document, null)
  has_inline_policy          = try(module.spoke-policy-${spoke_config.alias}-${service_name}.has_inline_policy, false)
  has_managed_policy         = false
  policy_arns                = {}
  %{endif~}
  %{if values.csoc_provider == "azure"~}
  csoc_managed_identity_id = %{if contains(keys(values.all_configs), service_name) && lookup(lookup(values.all_configs, service_name, {}), "enable_identity", false)~}module.pod-identity-${service_name}.identity_id%{else~}""%{endif}
  role_definition_json     = try(module.spoke-policy-${spoke_config.alias}-${service_name}.role_definition_json, null)
  has_role_definition      = try(module.spoke-policy-${spoke_config.alias}-${service_name}.has_role_definition, false)
  %{endif~}
  %{if values.csoc_provider == "gcp"~}
  csoc_workload_identity_email = %{if contains(keys(values.all_configs), service_name) && lookup(lookup(values.all_configs, service_name, {}), "enable_identity", false)~}module.pod-identity-${service_name}.service_account_email%{else~}""%{endif}
  role_definition_yaml         = try(module.spoke-policy-${spoke_config.alias}-${service_name}.role_definition_yaml, null)
  has_role_definition          = try(module.spoke-policy-${spoke_config.alias}-${service_name}.has_role_definition, false)
  %{endif~}

  tags = merge(
    var.tags,
    {
      spoke_alias  = "${spoke_config.alias}"
      service_name = "${service_name}"
      context      = "spoke"
    }
  )

  depends_on = [module.spoke-policy-${spoke_config.alias}-${service_name}]
}
%{endfor~}

%{endfor~}
EOF
}

###############################################################################
# Generate Cross-Account Policies
###############################################################################
generate "cross_account_policies" {
  path      = "cross_account_policies.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
###############################################################################
# Cross-Account Policies - Allow CSOC Pod Identities to Assume Spoke Roles
###############################################################################

%{for service_name, service_config in values.all_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "cross-account-${service_name}" {
  source = "./aws-cross-account-policy"

  create                     = var.enable_k8s_cluster
  service_name               = "${service_name}"
  csoc_pod_identity_role_arn = try(module.pod-identity-${service_name}.role_arn, "")

  # Collect all spoke role ARNs for this service
  # Skip spokes where account ID == csoc account ID (same account scenario)
  spoke_role_arns = compact([
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
    data.aws_caller_identity.${spoke_config.alias}.account_id != data.aws_caller_identity.csoc.account_id ? try(module.spoke-role-${spoke_config.alias}-${service_name}.role_arn, "") : "",
%{endif~}
%{endfor~}
  ])

  tags = merge(
    var.tags,
    {
      service_name = "${service_name}"
      context      = "cross-account"
    }
  )

  depends_on = [
    module.pod-identity-${service_name},
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
    module.spoke-role-${spoke_config.alias}-${service_name},
%{endif~}
%{endfor~}
  ]
}
%{endif~}
%{endfor~}
EOF
    : values.csoc_provider == "azure" ? <<-EOF
###############################################################################
# Cross-Subscription Policies - Allow CSOC Managed Identities to Access Spoke Resources
###############################################################################

# Azure uses federated credentials and role assignments instead of cross-account policies
# This is handled in the azure-spoke-role module

EOF
    : values.csoc_provider == "gcp" ? <<-EOF
###############################################################################
# Cross-Project Policies - Allow CSOC Workload Identities to Access Spoke Resources
###############################################################################

# GCP uses service account impersonation and IAM bindings instead of cross-account policies
# This is handled in the gcp-spoke-role module

EOF
    : ""
  )
}

###############################################################################
# Generate Variables
###############################################################################
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
variable "csoc_provider" {
  description = "Cloud provider for csoc cluster"
  type        = string
}

variable "csoc_iam_policies" {
  description = "Map of CSOC IAM policies by service name"
  type        = map(string)
}

variable "spoke_iam_policies" {
  description = "Map of spoke IAM policies by spoke alias"
  type        = map(map(string))
}

variable "addon_configs" {
  description = "All controller configurations (addons, ACK, ASO, GCC) with service details"
  type        = any
}

variable "cluster_name" {
  description = "CSOC cluster name"
  type        = string
}

variable "tags" {
  description = "Common tags for resources"
  type        = map(string)
}

variable "csoc_profile_name" {
  description = "AWS profile name for CSOC"
  type        = string
  default     = ""
}

variable "csoc_region" {
  description = "Region for CSOC cluster"
  type        = string
  default     = ""
}

variable "csoc_subscription_id" {
  description = "Azure subscription ID for CSOC"
  type        = string
  default     = ""
}

variable "csoc_project_id" {
  description = "GCP project ID for CSOC"
  type        = string
  default     = ""
}

variable "spokes" {
  description = "Spokes configuration"
  type        = any
}

variable "enable_k8s_cluster" {
  description = "Whether the Kubernetes cluster exists"
  type        = bool
  default     = false
}

variable "csoc_iam_policy_sources" {
  description = "Map of IAM policy sources for CSOC services (which folder was used)"
  type        = map(string)
  default     = {}
}

variable "spoke_iam_policy_sources" {
  description = "Map of IAM policy sources for spoke services by spoke alias (which folder was used)"
  type        = map(map(string))
  default     = {}
}

# Spoke provider variables (AWS)
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
variable "${spoke_config.alias}_profile" {
  description = "AWS profile for spoke ${spoke_config.alias}"
  type        = string
  default     = ""
}

variable "${spoke_config.alias}_region" {
  description = "AWS region for spoke ${spoke_config.alias}"
  type        = string
  default     = ""
}

variable "${spoke_config.alias}_subscription_id" {
  description = "Azure subscription ID for spoke ${spoke_config.alias}"
  type        = string
  default     = ""
}

variable "${spoke_config.alias}_project_id" {
  description = "GCP project ID for spoke ${spoke_config.alias}"
  type        = string
  default     = ""
}
%{endif~}
%{endfor~}
EOF
}

###############################################################################
# Generate Outputs
###############################################################################
generate "outputs" {
  path      = "outputs.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# IAM Configuration Outputs - Cloud-Agnostic
# Single unified output structure for all providers (AWS/Azure/GCP)
###############################################################################

# CSOC Identities - Controllers running in CSOC cluster
output "csoc_identities" {
  description = "Complete CSOC identity details for all controllers with provider-specific fields"
  value = {
%{for service_name, service_config in values.all_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = {
      # AWS-specific fields
      role_arn   = %{if values.csoc_provider == "aws"~}try(module.pod-identity-${service_name}.role_arn, "")%{else~}""%{endif}
      role_name  = %{if values.csoc_provider == "aws"~}try(module.pod-identity-${service_name}.role_name, "")%{else~}""%{endif}
      policy_arn = %{if values.csoc_provider == "aws"~}try(module.pod-identity-${service_name}.policy_arn, "")%{else~}""%{endif}

      # Azure-specific fields
      identity_id   = %{if values.csoc_provider == "azure"~}try(module.pod-identity-${service_name}.identity_id, "")%{else~}""%{endif}
      identity_name = %{if values.csoc_provider == "azure"~}try(module.pod-identity-${service_name}.identity_name, "")%{else~}""%{endif}
      client_id     = %{if values.csoc_provider == "azure"~}try(module.pod-identity-${service_name}.client_id, "")%{else~}""%{endif}

      # GCP-specific fields
      service_account_email = %{if values.csoc_provider == "gcp"~}try(module.pod-identity-${service_name}.service_account_email, "")%{else~}""%{endif}
      service_account_name  = %{if values.csoc_provider == "gcp"~}try(module.pod-identity-${service_name}.service_account_name, "")%{else~}""%{endif}

      # Common fields
      service_name              = "${service_name}"
      k8s_service_account       = "${lookup(service_config, "service_account", "${service_name}-sa")}"
      k8s_namespace             = "${lookup(service_config, "namespace", service_name)}"
      policy_source             = lookup(var.csoc_iam_policy_sources, "${service_name}", "_default")
    }
%{endif~}
%{endfor~}
  }
}

# Spoke Identities - Complete spoke information per controller
output "spoke_identities" {
  description = "Complete spoke identity details organized by spoke and controller with provider-specific fields"
  value = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    "${spoke_config.alias}" = {
      # Spoke-level metadata (provider-specific fields)
      # AWS fields
      account_id = %{if values.csoc_provider == "aws"~}try(data.aws_caller_identity.${spoke_config.alias}.account_id, "")%{else~}""%{endif}

      # Azure fields
      subscription_id = %{if values.csoc_provider == "azure"~}try(data.azurerm_client_config.${spoke_config.alias}.subscription_id, "")%{else~}""%{endif}
      tenant_id       = %{if values.csoc_provider == "azure"~}try(data.azurerm_client_config.${spoke_config.alias}.tenant_id, "")%{else~}""%{endif}

      # GCP fields
      project_id     = %{if values.csoc_provider == "gcp"~}try(data.google_project.${spoke_config.alias}.project_id, "")%{else~}""%{endif}
      project_number = %{if values.csoc_provider == "gcp"~}try(data.google_project.${spoke_config.alias}.number, "")%{else~}""%{endif}

      # Common fields
      region = var.${spoke_config.alias}_region

      # Controllers/services in this spoke
      controllers = {
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
        "${service_name}" = {
          # AWS-specific fields
          role_arn  = %{if values.csoc_provider == "aws"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.role_arn, "")%{else~}""%{endif}
          role_name = %{if values.csoc_provider == "aws"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.role_name, "")%{else~}""%{endif}

          # Azure-specific fields
          identity_id   = %{if values.csoc_provider == "azure"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.identity_id, "")%{else~}""%{endif}
          identity_name = %{if values.csoc_provider == "azure"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.identity_name, "")%{else~}""%{endif}
          client_id     = %{if values.csoc_provider == "azure"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.client_id, "")%{else~}""%{endif}

          # GCP-specific fields
          service_account_email = %{if values.csoc_provider == "gcp"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.service_account_email, "")%{else~}""%{endif}
          service_account_name  = %{if values.csoc_provider == "gcp"~}try(module.spoke-role-${spoke_config.alias}-${service_name}.service_account_name, "")%{else~}""%{endif}

          # Common fields
          service_name  = "${service_name}"
          policy_source = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "spoke_created")
        }
%{endfor~}
      }
    }
%{endif~}
%{endfor~}
  }
}
EOF
}
