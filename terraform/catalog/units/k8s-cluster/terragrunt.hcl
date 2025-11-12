###############################################################################
# CSOC K8s Cluster Unit Terragrunt Configuration
###############################################################################

terraform {
  source = "${values.catalog_path}//modules/${values.csoc_provider}-k8s-cluster"

  # After hook: When cluster was kept alive for ArgoCD cleanup, reapply after ArgoCD is destroyed
  after_hook "reapply_cluster_after_argocd_cleanup" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Only run if we prevented cluster disable for argocd
        if [[ "${local.prevent_cluster_disable_for_argocd}" == "true" ]]; then
          echo ""
          echo "═══════════════════════════════════════════════════════════════"
          echo "🔄 LIFECYCLE HOOK: Checking ArgoCD cleanup status"
          echo "═══════════════════════════════════════════════════════════════"
          echo "ℹ️  Cluster was kept alive because ArgoCD needs to be destroyed first."
          echo "🔍 Checking if ArgoCD has been cleaned up from state..."
          echo ""

          # Check if argocd state still has resources
          cd ${get_terragrunt_dir()}/../argocd
          if [[ ! -f terraform.tfstate ]]; then
            echo "⚠️  ArgoCD state file not found. Skipping reapply."
            exit 0
          fi

          argocd_resources=$(terraform state list 2>/dev/null | egrep '^kubernetes_|^helm_|^local_file\.' || true)

          if [[ -z "$argocd_resources" ]]; then
            echo "✅ ArgoCD has been removed from state."
            echo "🔄 Re-running cluster apply to proceed with cluster destroy..."
            echo ""
            cd ${get_terragrunt_dir()}
            terragrunt apply -auto-approve
            echo ""
            echo "✅ Cluster lifecycle hook completed successfully."
          else
            echo "⏳ ArgoCD still has resources in state:"
            echo "$argocd_resources" | head -5
            echo ""
            echo "⏸️  Cluster will remain active until ArgoCD is fully destroyed."
          fi
          echo "═══════════════════════════════════════════════════════════════"
          echo ""
        fi
      EOT
    ]
    run_on_error = false
  }

  # After hook: When VPC was kept alive for cluster cleanup, reapply after cluster is destroyed
  after_hook "reapply_vpc_after_cluster_cleanup" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Only run if vpc is disabled but cluster is enabled and vpc was in state
        if [[ "${local.vpc_disabled_but_in_state}" == "true" && "${local.enable_k8s_cluster}" == "true" ]]; then
          echo ""
          echo "═══════════════════════════════════════════════════════════════"
          echo "🔄 LIFECYCLE HOOK: Checking cluster cleanup status for VPC"
          echo "═══════════════════════════════════════════════════════════════"
          echo "ℹ️  VPC was kept alive because cluster needs to be destroyed first."
          echo "🔍 Checking if cluster has been cleaned up from state..."
          echo ""

          # Check if cluster state still has resources
          cluster_resources=$(terraform state list 2>/dev/null | egrep '^aws_eks_|^azurerm_kubernetes_|^google_container_|^module\\.eks\\.|^module\\.aks\\.|^module\\.gke\\.' || true)

          if [[ -z "$cluster_resources" ]]; then
            echo "✅ Cluster has been removed from state."
            echo "🔄 Re-running VPC apply to proceed with VPC destroy..."
            echo ""
            cd ${get_terragrunt_dir()}/../vpc
            terragrunt apply -auto-approve
            echo ""
            echo "✅ VPC lifecycle hook completed successfully."
          else
            echo "⏳ Cluster still has resources in state:"
            echo "$cluster_resources" | head -5
            echo ""
            echo "⏸️  VPC will remain active until cluster is fully destroyed."
          fi
          echo "═══════════════════════════════════════════════════════════════"
          echo ""
        fi
      EOT
    ]
    run_on_error = false
  }
}

###############################################################################
# Locals - Conditional Provider Logic
###############################################################################
locals {
  # Enable flag for k8s cluster
  enable_k8s_cluster = values.enable_k8s_cluster
  enable_argocd      = try(values.enable_argocd, false)
  enable_vpc         = try(values.enable_vpc, false)

  # Check if there are existing cluster resources in state
  # This allows destroy operations to work even when enable_k8s_cluster = false
  cluster_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && terraform state list 2>/dev/null | egrep '^aws_eks_|^azurerm_kubernetes_|^google_container_|^module\\.eks\\.|^module\\.aks\\.|^module\\.gke\\.' || true"
  )) != ""

  # Check if ArgoCD unit has resources in state
  argocd_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../argocd && (terraform init -backend=false -input=false >/dev/null 2>&1 || true) && terraform state list 2>/dev/null | egrep '^kubernetes_|^helm_|^local_file\\.' || true"
  )) != ""

  # Check if VPC unit has resources in state
  vpc_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../vpc && terraform state list 2>/dev/null | egrep '^aws_vpc|^azurerm_virtual_network|^google_compute_network|^module\\.vpc\\.|^module\\.vnet\\.' || true"
  )) != ""

  # Lifecycle management logic:
  # Case 1: cluster disabled, argocd disabled, argocd still in state
  #   → Do NOT disable cluster (keep create=true), use after_hook to reapply after argocd is destroyed
  prevent_cluster_disable_for_argocd = !local.enable_k8s_cluster && !local.enable_argocd && local.argocd_state_has_resources

  # Case 2: vpc disabled, k8s enabled, vpc still in state
  #   → VPC will not be disabled (handled in vpc unit), but track it here
  vpc_disabled_but_in_state = !local.enable_vpc && local.vpc_state_has_resources

  # Final create flag - override disable if we need to keep cluster for ArgoCD cleanup
  should_create_cluster = local.enable_k8s_cluster || local.prevent_cluster_disable_for_argocd

  # Need cluster-specific providers if cluster should be created OR if state has resources
  need_cluster_providers = local.should_create_cluster || local.cluster_state_has_resources
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
  description = "K8s Cluster lifecycle management status"
  value = {
    status = var.lifecycle_info.prevent_cluster_disable_for_argocd ? "⚠️  LIFECYCLE HOLD: Cluster kept alive for ArgoCD cleanup" : (
      var.lifecycle_info.enable_k8s_cluster ? "✅ Cluster enabled normally" : "⏸️  Cluster disabled normally"
    )

    details = var.lifecycle_info.prevent_cluster_disable_for_argocd ? {
      reason = "🔗 ArgoCD resources still exist in state and need cluster to be destroyed"
      action = "🔄 After ArgoCD is destroyed, cluster will be automatically reapplied and destroyed"
      argocd_in_state = var.lifecycle_info.argocd_state_has_resources
    } : {}

    flags = {
      enable_k8s_cluster = var.lifecycle_info.enable_k8s_cluster
      enable_argocd      = var.lifecycle_info.enable_argocd
      enable_vpc         = var.lifecycle_info.enable_vpc
    }

    computed = {
      should_create_cluster              = var.lifecycle_info.should_create_cluster
      prevent_cluster_disable_for_argocd = var.lifecycle_info.prevent_cluster_disable_for_argocd
    }
  }
}
EOF
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  # Module control - use computed should_create_cluster instead of enable_k8s_cluster directly
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

  # Lifecycle management debug info
  lifecycle_info = {
    enable_k8s_cluster                 = local.enable_k8s_cluster
    enable_argocd                      = local.enable_argocd
    enable_vpc                         = local.enable_vpc
    cluster_state_has_resources        = local.cluster_state_has_resources
    argocd_state_has_resources         = local.argocd_state_has_resources
    vpc_state_has_resources            = local.vpc_state_has_resources
    prevent_cluster_disable_for_argocd = local.prevent_cluster_disable_for_argocd
    vpc_disabled_but_in_state          = local.vpc_disabled_but_in_state
    should_create_cluster              = local.should_create_cluster
  }
}
