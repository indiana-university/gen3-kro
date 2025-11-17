###############################################################################
# CSOC K8s Cluster Unit Terragrunt Configuration
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/${values.csoc_provider}-k8s-cluster"
}

###############################################################################
# Locals
###############################################################################
locals {
  # Check if k8s-controller-req unit has resources in state (unified unit)
  k8s_controller_req_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-controller-req 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )
  # Check if k8s-spoke-req unit has resources in state
  k8s_spoke_req_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-spoke-req 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )
  # Check if k8s-argocd-core unit has resources in state
  argocd_core_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-argocd-core 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'helm_release|kubernetes_' || true"
  )

  k8s_controller_req_has_state = trimspace(local.k8s_controller_req_state_check_output) != ""
  k8s_spoke_req_has_state      = trimspace(local.k8s_spoke_req_state_check_output) != ""
  argocd_core_has_state        = trimspace(local.argocd_core_state_check_output) != ""

  # Cluster stays alive if any k8s units have resources
  has_dependent_resources = local.k8s_controller_req_has_state || local.k8s_spoke_req_has_state || local.argocd_core_has_state
  should_create_cluster   = values.enable_k8s_cluster || local.has_dependent_resources
}

###############################################################################
# Dependencies
###############################################################################
# Dependency: VPC Unit (vpc_id, subnet IDs, state check results)
dependency "csoc_vpc" {
  config_path = "../vpc"

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    vpc_id                      = "vpc-mock123456"
    private_subnets             = ["subnet-mock1", "subnet-mock2", "subnet-mock3"]
    public_subnets              = ["subnet-mock4", "subnet-mock5", "subnet-mock6"]
    argocd_state_has_resources  = false
    cluster_state_has_resources = false
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
  # Module control - use computed should_create_cluster
  create = local.should_create_cluster

  # Basic configuration
  tags          = values.tags
  cluster_name  = values.cluster_name
  region        = values.region

  # VPC inputs from vpc unit dependency
  # Use mock values if VPC returns empty (when enable_vpc=false but vpc kept alive for dependencies)
  vpc_id = try(
    length(dependency.csoc_vpc.outputs.vpc_id) > 0 ? dependency.csoc_vpc.outputs.vpc_id : "vpc-mock123456",
    "vpc-mock123456"
  )
  subnet_ids = try(
    length(dependency.csoc_vpc.outputs.private_subnets) > 0 || length(dependency.csoc_vpc.outputs.public_subnets) > 0 ? concat(
      dependency.csoc_vpc.outputs.private_subnets,
      dependency.csoc_vpc.outputs.public_subnets
    ) : ["subnet-mock1", "subnet-mock2", "subnet-mock3", "subnet-mock4", "subnet-mock5", "subnet-mock6"],
    ["subnet-mock1", "subnet-mock2", "subnet-mock3", "subnet-mock4", "subnet-mock5", "subnet-mock6"]
  )

  # Kubernetes cluster configuration
  cluster_version                          = values.cluster_version
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = values.cluster_compute_config
}
