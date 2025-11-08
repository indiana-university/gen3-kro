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
  create = values.enable_vpc

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
