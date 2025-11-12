###############################################################################
# CSOC VPC Unit Terragrunt Configuration
#
# This unit creates the VPC infrastructure for the CSOC (hub) cluster.
# It has no dependencies and provides VPC outputs to the csoc unit.
###############################################################################

terraform {
  source = "${values.catalog_path}//modules/${values.csoc_provider == "azure" ? "azure-vnet" : "${values.csoc_provider}-vpc"}"
}

###############################################################################
# Locals - Lifecycle Management
###############################################################################
locals {
  enable_vpc         = values.enable_vpc
  enable_k8s_cluster = try(values.enable_k8s_cluster, false)

  backend_configured = (
    (values.csoc_provider == "aws"   && values.state_bucket != "") ||
    (values.csoc_provider == "azure" && values.state_storage_account != "" && values.state_container != "") ||
    (values.csoc_provider == "gcp"   && values.state_bucket != "")
  )

  # Check if VPC has resources in state
  vpc_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && terraform state list 2>/dev/null | egrep '^aws_vpc|^azurerm_virtual_network|^google_compute_network|^module\\.vpc\\.|^module\\.vnet\\.' || true"
  )) != ""

  # Check if k8s cluster has resources in state
  cluster_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-cluster && terraform state list 2>/dev/null | egrep '^aws_eks_|^azurerm_kubernetes_|^google_container_|^module\\.eks\\.|^module\\.aks\\.|^module\\.gke\\.' || true"
  )) != ""

  # Lifecycle management logic:
  # vpc disabled, k8s enabled, cluster still in state
  #   → Do NOT disable VPC (keep create=true), let k8s-cluster handle cleanup
  prevent_vpc_disable_for_cluster = !local.enable_vpc && local.enable_k8s_cluster && local.cluster_state_has_resources

  # Final create flag
  should_create_vpc = local.enable_vpc || local.prevent_vpc_disable_for_cluster
}

###############################################################################
# Generate Files
###############################################################################

# Generate backend configuration for csoc-vpc state
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = local.backend_configured ? (
    values.csoc_provider == "aws" ? <<EOF
terraform {
  backend "s3" {
    bucket  = "${values.state_bucket}"
    key     = "${values.csoc_alias}/units/vpc/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/vpc/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/vpc"
  }
}
EOF
    : ""
  ) : ""
}

###############################################################################
# Lifecycle Management Output
###############################################################################
generate "lifecycle_output" {
  path      = "lifecycle_info.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
variable "lifecycle_info" {
  description = "Lifecycle management debug information"
  type        = any
  default     = {}
}

output "lifecycle_management" {
  description = "VPC lifecycle management status"
  value = {
    status = var.lifecycle_info.prevent_vpc_disable_for_cluster ? "⚠️  LIFECYCLE HOLD: VPC kept alive for cluster cleanup" : (
      var.lifecycle_info.enable_vpc ? "✅ VPC enabled normally" : "⏸️  VPC disabled normally"
    )

    details = var.lifecycle_info.prevent_vpc_disable_for_cluster ? {
      reason = "🔗 K8s cluster resources still exist in state and need VPC to be destroyed"
      action = "🔄 After cluster is destroyed, VPC will be automatically reapplied and destroyed"
      cluster_in_state = var.lifecycle_info.cluster_state_has_resources
    } : {}

    flags = {
      enable_vpc         = var.lifecycle_info.enable_vpc
      enable_k8s_cluster = var.lifecycle_info.enable_k8s_cluster
    }

    computed = {
      should_create_vpc               = var.lifecycle_info.should_create_vpc
      prevent_vpc_disable_for_cluster = var.lifecycle_info.prevent_vpc_disable_for_cluster
    }
  }
}
EOF
}

###############################################################################
# Inputs for CSOC VPC Unit
###############################################################################

inputs = {
  # Module control - use computed should_create_vpc instead of enable_vpc directly
  create = local.should_create_vpc

  # Global settings
  tags         = values.tags
  cluster_name = values.cluster_name

  # VPC configuration from stack values
  vpc_name             = values.vpc_name
  vpc_cidr             = values.vpc_cidr
  enable_nat_gateway   = values.enable_nat_gateway
  single_nat_gateway   = values.single_nat_gateway
  public_subnet_tags   = values.public_subnet_tags
  private_subnet_tags  = values.private_subnet_tags
  availability_zones   = values.availability_zones
  private_subnet_cidrs = values.private_subnet_cidrs
  public_subnet_cidrs  = values.public_subnet_cidrs

  # Lifecycle management debug info
  lifecycle_info = {
    enable_vpc                      = local.enable_vpc
    enable_k8s_cluster              = local.enable_k8s_cluster
    vpc_state_has_resources         = local.vpc_state_has_resources
    cluster_state_has_resources     = local.cluster_state_has_resources
    prevent_vpc_disable_for_cluster = local.prevent_vpc_disable_for_cluster
    should_create_vpc               = local.should_create_vpc
  }
}
###############################################################################
# End of File
###############################################################################
