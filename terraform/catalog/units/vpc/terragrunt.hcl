###############################################################################
# CSOC VPC Unit Terragrunt Configuration
#
# This unit creates the VPC infrastructure for the CSOC (hub) cluster.
# It has no dependencies and provides VPC outputs to the csoc unit.
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/${values.csoc_provider == "azure" ? "azure-vnet" : "${values.csoc_provider}-vpc"}"
}

###############################################################################
# Locals
###############################################################################
locals {
  # Check if k8s cluster unit has resources in state
  k8s_cluster_state_check_cmd_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-cluster 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'aws_eks_|azurerm_kubernetes_|google_container_|module\\.eks\\.|module\\.aks\\.|module\\.gke\\.' || true"
  )
  k8s_cluster_unit_has_state = trimspace(local.k8s_cluster_state_check_cmd_output) != ""

  # Keep VPC alive if k8s-cluster exists in state
  should_create_vpc = values.enable_vpc || local.k8s_cluster_unit_has_state
}

###############################################################################
# Generate Files
###############################################################################

# Generate backend configuration for csoc-vpc state
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
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
  )
}

###############################################################################
# Inputs for CSOC VPC Unit
###############################################################################

inputs = {
  # Module control
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
}
###############################################################################
# End of File
###############################################################################
