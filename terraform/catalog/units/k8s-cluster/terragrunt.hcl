###############################################################################
# CSOC K8s Cluster Unit Terragrunt Configuration
###############################################################################

terraform {
  source = "${values.catalog_path}//modules/${values.csoc_provider}-k8s-cluster"
}

###############################################################################
# Locals - Conditional Provider Logic
###############################################################################
locals {
  # Enable flag for k8s cluster
  enable_k8s_cluster = values.enable_k8s_cluster

  # Check if there are existing cluster resources in state
  # This allows destroy operations to work even when enable_k8s_cluster = false
  cluster_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && terraform state list 2>/dev/null | egrep '^aws_eks_|^azurerm_kubernetes_|^google_container_|^module\\.eks\\.|^module\\.aks\\.|^module\\.gke\\.' || true"
  )) != ""

  # Need cluster-specific providers if cluster is enabled OR if state has resources
  need_cluster_providers = local.enable_k8s_cluster || local.cluster_state_has_resources
}

###############################################################################
# Dependencies
###############################################################################
# Dependency: VPC Unit (vpc_id, subnet IDs)
dependency "csoc_vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
  mock_outputs = {
    vpc_id           = "vpc-mock123456"
    private_subnets  = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    public_subnets   = ["subnet-mock4", "subnet-mock5", "subnet-mock6"]
  }
}

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
    key     = "${values.csoc_alias}/units/k8s-cluster/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/k8s-cluster/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/k8s-cluster"
  }
}
EOF
    : ""
  )
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  # Module control
  create = local.enable_k8s_cluster

  # Basic configuration
  tags          = values.tags
  cluster_name  = values.cluster_name
  region        = values.region

  # VPC inputs from vpc unit dependency
  vpc_id = dependency.csoc_vpc.outputs.vpc_id
  subnet_ids = concat(
    dependency.csoc_vpc.outputs.private_subnets,
    dependency.csoc_vpc.outputs.public_subnets
  )

  # Kubernetes cluster configuration
  cluster_version                          = values.cluster_version
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = values.cluster_compute_config
}

###############################################################################
# Outputs Directory
###############################################################################
