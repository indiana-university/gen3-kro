###############################################################################
# IAM Configuration Unit Terragrunt Configuration
#
# This unit creates:
# 1. CSOC pod identity roles (for controllers running in CSOC cluster)
# 2. Cross-account policies (allowing CSOC pods to assume spoke roles)
# 3. Spoke IAM roles (for spoke account resources)
###############################################################################

terraform {
  source = "${values.catalog_path}//modules"
}
###############################################################################
# Dependencies
###############################################################################
dependency "csoc" {
  config_path = "../k8s-cluster"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
  mock_outputs = {
    cluster_name = "mock-csoc-cluster"
    cluster_id   = null
    cluster_arn  = null
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

    # Addon configurations
    addon_configs = values.addon_configs

    # Cluster existence flag - both config flag AND actual cluster must exist
    # AWS uses cluster_arn, Azure/GCP use cluster_id
    enable_k8s_cluster = values.enable_k8s_cluster && (
      values.csoc_provider == "aws" ? (
        dependency.csoc.outputs.cluster_arn != null &&
        dependency.csoc.outputs.cluster_arn != "" &&
        !can(regex("^mock-", dependency.csoc.outputs.cluster_name))
      ) : (
        dependency.csoc.outputs.cluster_id != null &&
        dependency.csoc.outputs.cluster_id != "" &&
        !can(regex("^mock-", dependency.csoc.outputs.cluster_name))
      )
    )

    # Provider-specific configuration
    csoc_profile_name = values.profile
    project_id        = values.project_id

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
data "azurerm_client_config" "csoc" {}


# Spoke Subscription Data Sources (for cross-subscription comparison)
%{for spoke_config in values.spokes_config~}
data "azurerm_client_config" "${spoke_config.alias}" {
  provider = azurerm.${spoke_config.alias}
}
%{endfor~}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
# CSOC GCP Data Sources
data "google_client_config" "csoc" {}

data "google_project" "csoc" {
  project_id = var.project_id
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
# CSOC IAM Policies - For Pod Identity Roles
###############################################################################

%{for service_name, policy_json in values.csoc_iam_policies~}
module "csoc_policy_${service_name}" {
  source = "./iam-policy"

  service_name       = "${service_name}"
  policy_inline_json = ${jsonencode(policy_json)}

  account_id      = data.aws_caller_identity.csoc.account_id
  csoc_account_id = data.aws_caller_identity.csoc.account_id
  policy_source   = lookup(var.csoc_iam_policy_sources, "${service_name}", "_default")
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
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
###############################################################################
# CSOC Pod Identity Roles - Controllers running in CSOC cluster
###############################################################################

%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "pod_identity_${service_name}" {
  source = "./aws-pod-identity"

  create       = var.enable_k8s_cluster
  cluster_name = var.cluster_name
  context      = "csoc"

  service_name    = "${service_name}"

  # Multi-spoke associations: create service accounts per spoke
  spoke_associations = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    ${spoke_config.alias} = {
      namespace       = "${lookup(service_config, "namespace", "kube-system")}"
      service_account = "${lookup(service_config, "service_account", replace(service_name, "_", "-"))}"
      spoke_alias     = "${spoke_config.alias}"
    }
%{endif~}
%{endfor~}
  }

  loaded_inline_policy_document = try(module.csoc_policy_${service_name}.inline_policy_document, "")
  has_loaded_inline_policy      = try(module.csoc_policy_${service_name}.has_inline_policy, false)

  tags = merge(
    var.tags,
    {
      service_name = "${service_name}"
      context      = "csoc"
    }
  )

  depends_on = [module.csoc_policy_${service_name}]
}
%{endif~}
%{endfor~}
EOF
    : values.csoc_provider == "azure" ? <<-EOF
###############################################################################
# CSOC Managed Identity - Controllers running in CSOC cluster
###############################################################################

%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "managed_identity_${service_name}" {
  source = "./azure-managed-identity"

  create       = var.enable_k8s_cluster
  cluster_name = var.cluster_name
  context      = "csoc"

  service_name    = "${service_name}"
  namespace       = "${lookup(service_config, "namespace", "kube-system")}"
  service_account = "${lookup(service_config, "service_account", replace(service_name, "_", "-"))}"

  role_definition_json = try(module.csoc_policy_${service_name}.role_definition_json, "")
  has_role_definition  = try(module.csoc_policy_${service_name}.has_role_definition, false)

  tags = merge(
    var.tags,
    {
      service_name = "${service_name}"
      context      = "csoc"
    }
  )

  depends_on = [module.csoc_policy_${service_name}]
}
%{endif~}
%{endfor~}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
###############################################################################
# CSOC Workload Identity - Controllers running in CSOC cluster
###############################################################################

%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "workload_identity_${service_name}" {
  source = "./gcp-workload-identity"

  create       = var.enable_k8s_cluster
  cluster_name = var.cluster_name
  context      = "csoc"

  service_name    = "${service_name}"
  namespace       = "${lookup(service_config, "namespace", "kube-system")}"
  service_account = "${lookup(service_config, "service_account", replace(service_name, "_", "-"))}"

  role_definition_yaml = try(module.csoc_policy_${service_name}.role_definition_yaml, "")
  has_role_definition  = try(module.csoc_policy_${service_name}.has_role_definition, false)

  tags = merge(
    var.tags,
    {
      service_name = "${service_name}"
      context      = "csoc"
    }
  )

  depends_on = [module.csoc_policy_${service_name}]
}
%{endif~}
%{endfor~}
EOF
    : ""
  )
}

###############################################################################
# Generate Spoke Provider Configurations
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
}

###############################################################################
# Spoke Provider Configurations - AWS
###############################################################################

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
###############################################################################
# Spoke Provider Configurations - Azure
###############################################################################

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
###############################################################################
# Spoke Provider Configurations - GCP
###############################################################################

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
# Generate Spoke IAM Policies
###############################################################################
generate "spoke_policies" {
  path      = "spoke_policies.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# Spoke IAM Policies - For Spoke Roles
###############################################################################

%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
# Policies for ${spoke_config.alias}
%{for service_name, policy_json in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke_policy_${spoke_config.alias}_${service_name}" {
  source = "./iam-policy"

  service_name       = "${service_name}"
  policy_inline_json = ${jsonencode(policy_json)}

  account_id      = data.aws_caller_identity.${spoke_config.alias}.account_id
  csoc_account_id = data.aws_caller_identity.csoc.account_id
  policy_source   = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "_default")
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
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
###############################################################################
# Spoke IAM Roles - Trusted by CSOC Pod Identities
###############################################################################

%{for spoke_config in values.spokes_config~}
# Roles for ${spoke_config.alias}
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke_role_${spoke_config.alias}_${service_name}" {
  source = "./aws-spoke-role"

  providers = {
    aws = aws.${spoke_config.alias}
  }

  # Skip creation if spoke account == csoc account (same account scenario)
  # In that case, we'll use the csoc pod identity role directly via override_id
  create                     = ${lookup(spoke_config, "enabled", false)} && var.enable_k8s_cluster && ${lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)} && data.aws_caller_identity.${spoke_config.alias}.account_id != data.aws_caller_identity.csoc.account_id
  override_id                = data.aws_caller_identity.${spoke_config.alias}.account_id == data.aws_caller_identity.csoc.account_id ? (%{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.pod_identity_${service_name}.role_arn%{else~}""%{endif~}) : null
  cluster_name               = var.cluster_name
  service_name               = "${service_name}"
  spoke_alias                = "${spoke_config.alias}"
  csoc_pod_identity_role_arn = %{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.pod_identity_${service_name}.role_arn%{else~}""%{endif~}

  combined_policy_json = try(module.spoke_policy_${spoke_config.alias}_${service_name}.inline_policy_document, null)
  has_inline_policy    = try(module.spoke_policy_${spoke_config.alias}_${service_name}.has_inline_policy, false)
  has_managed_policy   = false
  policy_arns          = {}

  tags = merge(
    var.tags,
    {
      spoke_alias  = "${spoke_config.alias}"
      service_name = "${service_name}"
      context      = "spoke"
    }
  )

  depends_on = [module.spoke_policy_${spoke_config.alias}_${service_name}]
}
%{endfor~}

%{endfor~}
EOF
    : values.csoc_provider == "azure" ? <<-EOF
###############################################################################
# Spoke Managed Identities - Trusted by CSOC Managed Identities
###############################################################################

%{for spoke_config in values.spokes_config~}
# Managed Identities for ${spoke_config.alias}
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke_identity_${spoke_config.alias}_${service_name}" {
  source = "./azure-spoke-role"

  providers = {
    azurerm = azurerm.${spoke_config.alias}
  }

  # Skip creation if spoke subscription == csoc subscription (same subscription scenario)
  # In that case, we'll use the csoc managed identity directly via override_id
  create                        = lookup(spoke_config, "enabled", false) && var.enable_k8s_cluster && data.azurerm_client_config.${spoke_config.alias}.subscription_id != data.azurerm_client_config.csoc.subscription_id
  override_id                   = data.azurerm_client_config.${spoke_config.alias}.subscription_id == data.azurerm_client_config.csoc.subscription_id ? (%{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.managed_identity_${service_name}.identity_id%{else~}""%{endif~}) : null
  cluster_name                  = var.cluster_name
  service_name                  = "${service_name}"
  spoke_alias                   = "${spoke_config.alias}"
  csoc_managed_identity_id      = %{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.managed_identity_${service_name}.identity_id%{else~}""%{endif~}

  role_definition_json = try(module.spoke_policy_${spoke_config.alias}_${service_name}.role_definition_json, null)
  has_role_definition  = try(module.spoke_policy_${spoke_config.alias}_${service_name}.has_role_definition, false)

  tags = merge(
    var.tags,
    {
      spoke_alias  = "${spoke_config.alias}"
      service_name = "${service_name}"
      context      = "spoke"
    }
  )

  depends_on = [module.spoke_policy_${spoke_config.alias}_${service_name}]
}
%{endfor~}

%{endfor~}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
###############################################################################
# Spoke Service Accounts - Trusted by CSOC Workload Identities
###############################################################################

%{for spoke_config in values.spokes_config~}
# Service Accounts for ${spoke_config.alias}
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
module "spoke_sa_${spoke_config.alias}_${service_name}" {
  source = "./gcp-spoke-role"

  providers = {
    google = google.${spoke_config.alias}
  }

  # Skip creation if spoke project == csoc project (same project scenario)
  # In that case, we'll use the csoc workload identity directly via override_id
  create                          = lookup(spoke_config, "enabled", false) && var.enable_k8s_cluster && data.google_project.${spoke_config.alias}.project_id != data.google_project.csoc.project_id
  override_id                     = data.google_project.${spoke_config.alias}.project_id == data.google_project.csoc.project_id ? (%{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.workload_identity_${service_name}.service_account_email%{else~}""%{endif~}) : null
  cluster_name                    = var.cluster_name
  service_name                    = "${service_name}"
  spoke_alias                     = "${spoke_config.alias}"
  csoc_workload_identity_email    = %{if contains(keys(values.addon_configs), service_name) && lookup(lookup(values.addon_configs, service_name, {}), "enable_identity", false)~}module.workload_identity_${service_name}.service_account_email%{else~}""%{endif~}

  role_definition_yaml = try(module.spoke_policy_${spoke_config.alias}_${service_name}.role_definition_yaml, null)
  has_role_definition  = try(module.spoke_policy_${spoke_config.alias}_${service_name}.has_role_definition, false)

  tags = merge(
    var.tags,
    {
      spoke_alias  = "${spoke_config.alias}"
      service_name = "${service_name}"
      context      = "spoke"
    }
  )

  depends_on = [module.spoke_policy_${spoke_config.alias}_${service_name}]
}
%{endfor~}

%{endfor~}
EOF
    : ""
  )
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

%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
module "cross_account_${service_name}" {
  source = "./aws-cross-account-policy"

  create                     = var.enable_k8s_cluster
  service_name               = "${service_name}"
  csoc_pod_identity_role_arn = try(module.pod_identity_${service_name}.role_arn, "")

  # Collect all spoke role ARNs for this service
  # Skip spokes where account ID == csoc account ID (same account scenario)
  spoke_role_arns = compact([
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
    data.aws_caller_identity.${spoke_config.alias}.account_id != data.aws_caller_identity.csoc.account_id ? try(module.spoke_role_${spoke_config.alias}_${service_name}.role_arn, "") : "",
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
    module.pod_identity_${service_name},
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
    module.spoke_role_${spoke_config.alias}_${service_name},
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
  description = "Addon configurations with service details"
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
  description = "AWS profile name for CSOC to get account ID"
  type        = string
  default     = ""
}

variable "project_id" {
  description = "GCP project ID"
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
  contents = (
    values.csoc_provider == "aws" ? <<-EOF
###############################################################################
# IAM Configuration Outputs - AWS
###############################################################################

# CSOC Pod Identity Role ARNs (by service name)
output "csoc_pod_identity_arns" {
  description = "Map of CSOC pod identity role ARNs by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = try(module.pod_identity_${service_name}.role_arn, "")
%{endif~}
%{endfor~}
  }
}

# CSOC Pod Identity Details (full objects for configmap)
output "csoc_pod_identity_details" {
  description = "Map of CSOC pod identity details by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = {
      role_arn      = try(module.pod_identity_${service_name}.role_arn, "")
      role_name     = try(module.pod_identity_${service_name}.role_name, "")
      policy_arn    = try(module.pod_identity_${service_name}.policy_arn, "")
      service_name  = try(module.pod_identity_${service_name}.service_name, "${service_name}")
      policy_source = try(module.csoc_policy_${service_name}.policy_source, "_default")
    }
%{endif~}
%{endfor~}
  }
}

# Spoke service roles aggregated by controller (for k8s-cluster unit)
output "spoke_service_roles_by_controller" {
  description = "Map of spoke role ARNs by controller/service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = compact([
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
      try(module.spoke_role_${spoke_config.alias}_${service_name}.role_arn, ""),
%{endif~}
%{endfor~}
    ])
%{endif~}
%{endfor~}
  }
}

# Individual spoke outputs
output "spokes_all_service_roles" {
  description = "Map of all service roles by spoke alias"
  value = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    "${spoke_config.alias}" = {
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
      "${service_name}" = {
        role_arn     = try(module.spoke_role_${spoke_config.alias}_${service_name}.role_arn, "")
        service_name = "${service_name}"
        spoke_alias  = "${spoke_config.alias}"
        source       = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "spoke_created")
      }
%{endfor~}
    }
%{endif~}
%{endfor~}
  }
}

# Cross-account policy ARNs
output "cross_account_policy_arns" {
  description = "Map of cross-account policy ARNs by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = try(module.cross_account_${service_name}.policy_arn, null)
%{endif~}
%{endfor~}
  }
}

# Debug: spokes provider info and account IDs
output "spoke_provider_debug" {
  description = "Map of spokes -> { profile, region, account_id } for debugging"
  value = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    "${spoke_config.alias}" = {
      profile    = var.${spoke_config.alias}_profile
      region     = var.${spoke_config.alias}_region
      account_id = try(data.aws_caller_identity.${spoke_config.alias}.account_id, "")
    }
%{endif~}
%{endfor~}
  }
}
EOF
    : values.csoc_provider == "azure" ? <<-EOF
###############################################################################
# IAM Configuration Outputs - Azure
###############################################################################

# CSOC Managed Identity IDs (by service name)
output "csoc_pod_identity_arns" {
  description = "Map of CSOC managed identity IDs by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = try(module.managed_identity_${service_name}.identity_id, "")
%{endif~}
%{endfor~}
  }
}

# CSOC Managed Identity Details (full objects for configmap)
output "csoc_pod_identity_details" {
  description = "Map of CSOC managed identity details by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = {
      role_arn      = try(module.managed_identity_${service_name}.identity_id, "")
      role_name     = try(module.managed_identity_${service_name}.identity_name, "")
      policy_arn    = ""
      service_name  = "${service_name}"
      policy_source = "azure_role"
    }
%{endif~}
%{endfor~}
  }
}

# Spoke managed identities aggregated by controller
output "spoke_service_roles_by_controller" {
  description = "Map of spoke managed identity IDs by controller/service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = compact([
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
      try(module.spoke_identity_${spoke_config.alias}_${service_name}.identity_id, ""),
%{endif~}
%{endfor~}
    ])
%{endif~}
%{endfor~}
  }
}

# Individual spoke outputs
output "spokes_all_service_roles" {
  description = "Map of all managed identities by spoke alias"
  value = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    "${spoke_config.alias}" = {
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
      "${service_name}" = {
        role_arn     = try(module.spoke_identity_${spoke_config.alias}_${service_name}.identity_id, "")
        service_name = "${service_name}"
        spoke_alias  = "${spoke_config.alias}"
        source       = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "spoke_created")
      }
%{endfor~}
    }
%{endif~}
%{endfor~}
  }
}

# Cross-subscription policy ARNs (not used in Azure)
output "cross_account_policy_arns" {
  description = "Map of cross-subscription policies (N/A for Azure)"
  value       = {}
}
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
###############################################################################
# IAM Configuration Outputs - GCP
###############################################################################

# CSOC Workload Identity Service Accounts (by service name)
output "csoc_pod_identity_arns" {
  description = "Map of CSOC workload identity service account emails by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = try(module.workload_identity_${service_name}.service_account_email, "")
%{endif~}
%{endfor~}
  }
}

# CSOC Workload Identity Details (full objects for configmap)
output "csoc_pod_identity_details" {
  description = "Map of CSOC workload identity details by service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = {
      role_arn      = try(module.workload_identity_${service_name}.service_account_email, "")
      role_name     = try(module.workload_identity_${service_name}.service_account_name, "")
      policy_arn    = ""
      service_name  = "${service_name}"
      policy_source = "gcp_role"
    }
%{endif~}
%{endfor~}
  }
}

# Spoke service accounts aggregated by controller
output "spoke_service_roles_by_controller" {
  description = "Map of spoke service account emails by controller/service name"
  value = {
%{for service_name, service_config in values.addon_configs~}
%{if lookup(service_config, "enable_identity", false)~}
    "${service_name}" = compact([
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false) && contains(keys(lookup(values.spoke_iam_policies, spoke_config.alias, {})), service_name)~}
      try(module.spoke_sa_${spoke_config.alias}_${service_name}.service_account_email, ""),
%{endif~}
%{endfor~}
    ])
%{endif~}
%{endfor~}
  }
}

# Individual spoke outputs
output "spokes_all_service_roles" {
  description = "Map of all service accounts by spoke alias"
  value = {
%{for spoke_config in values.spokes_config~}
%{if lookup(spoke_config, "enabled", false)~}
    "${spoke_config.alias}" = {
%{for service_name, _ in lookup(values.spoke_iam_policies, spoke_config.alias, {})~}
      "${service_name}" = {
        role_arn     = try(module.spoke_sa_${spoke_config.alias}_${service_name}.service_account_email, "")
        service_name = "${service_name}"
        spoke_alias  = "${spoke_config.alias}"
        source       = lookup(lookup(var.spoke_iam_policy_sources, "${spoke_config.alias}", {}), "${service_name}", "spoke_created")
      }
%{endfor~}
    }
%{endif~}
%{endfor~}
  }
}

# Cross-project policy ARNs (not used in GCP)
output "cross_account_policy_arns" {
  description = "Map of cross-project policies (N/A for GCP)"
  value       = {}
}
EOF
    : ""
  )
}
