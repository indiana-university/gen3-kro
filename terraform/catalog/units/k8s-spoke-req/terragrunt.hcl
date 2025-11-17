###############################################################################
# K8s Spoke Requirements Unit Terragrunt Configuration
# Manages spoke namespaces and spoke charter configmaps
# Provider-agnostic unit for Kubernetes infrastructure
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/k8s-spoke-req"

  # After Hook 1: Remove k8s-argocd-core from Terraform state
  after_hook "remove_argocd_core_state" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Check if we should remove k8s-argocd-core state
        SHOULD_REMOVE="${local.should_remove_argocd_core_state}"

        if [ "$SHOULD_REMOVE" = "true" ]; then
          echo "Removing k8s-argocd-core from Terraform state..."

          STACK_DIR="${get_terragrunt_dir()}/.."

          if [ -d "$STACK_DIR/k8s-argocd-core" ]; then
            cd "$STACK_DIR/k8s-argocd-core"
            CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname)
            if [ -n "$CACHE_DIR" ]; then
              cd "$CACHE_DIR"
              echo "Removing all k8s-argocd-core resources from state..."
              terraform state list 2>/dev/null | xargs -r -n1 terraform state rm 2>/dev/null || true
            fi
          fi
        else
          echo "Skipping k8s-argocd-core state removal (not needed)"
        fi
      EOT
    ]
    run_on_error = false
  }

  # After Hook 2: Remove k8s-controller-req from Terraform state
  after_hook "remove_controller_req_state" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Check if we should remove controller-req state
        SHOULD_REMOVE="${local.should_remove_controller_req_state}"

        if [ "$SHOULD_REMOVE" = "true" ]; then
          echo "Removing k8s-controller-req from Terraform state..."

          STACK_DIR="${get_terragrunt_dir()}/.."

          if [ -d "$STACK_DIR/k8s-controller-req" ]; then
            cd "$STACK_DIR/k8s-controller-req"
            CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname)
            if [ -n "$CACHE_DIR" ]; then
              cd "$CACHE_DIR"
              echo "Removing all k8s-controller-req resources from state..."
              terraform state list 2>/dev/null | xargs -r -n1 terraform state rm 2>/dev/null || true
            fi
          fi
        else
          echo "Skipping k8s-controller-req state removal (not needed)"
        fi
      EOT
    ]
    run_on_error = false
  }

  # After Hook 3: Destroy iam-config state
  after_hook "destroy_iam_config_state" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Check if we should destroy iam-config
        SHOULD_DESTROY="${local.should_destroy_iam_config}"

        if [ "$SHOULD_DESTROY" = "true" ]; then
          echo "Destroying iam-config Terraform state..."

          STACK_DIR="${get_terragrunt_dir()}/.."

          if [ -d "$STACK_DIR/iam-config" ]; then
            cd "$STACK_DIR/iam-config"
            terragrunt destroy -auto-approve || true
          fi
        else
          echo "Skipping iam-config destroy (not needed)"
        fi
      EOT
    ]
    run_on_error = false
  }

  # After Hook 4: Reapply k8s cluster
  after_hook "reapply_k8s_cluster" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Check if we should reapply infrastructure
        SHOULD_REAPPLY="${local.should_reapply_infrastructure}"

        if [ "$SHOULD_REAPPLY" = "true" ]; then
          echo "Reapplying k8s-cluster unit..."

          STACK_DIR="${get_terragrunt_dir()}/.."

          if [ -d "$STACK_DIR/k8s-cluster" ]; then
            cd "$STACK_DIR/k8s-cluster"
            terragrunt apply -auto-approve || true
          fi
        else
          echo "Skipping k8s-cluster reapply (not needed)"
        fi
      EOT
    ]
    run_on_error = false
  }

  # After Hook 5: Reapply VPC
  after_hook "reapply_vpc" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      <<-EOT
        set -e

        # Check if we should reapply infrastructure
        SHOULD_REAPPLY="${local.should_reapply_infrastructure}"

        if [ "$SHOULD_REAPPLY" = "true" ]; then
          echo "Reapplying vpc unit..."

          STACK_DIR="${get_terragrunt_dir()}/.."

          if [ -d "$STACK_DIR/vpc" ]; then
            cd "$STACK_DIR/vpc"
            terragrunt apply -auto-approve || true
          fi
        else
          echo "Skipping vpc reapply (not needed)"
        fi
      EOT
    ]
    run_on_error = false
  }
}

###############################################################################
# Locals
###############################################################################
locals {
  # Check if there are existing resources in state
  state_check_cmd_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )
  # Check if k8s-argocd-core unit has resources in state
  k8s_argocd_core_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-argocd-core 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'helm_release|kubernetes_' || true"
  )
  # Check if k8s-controller-req unit has resources in state
  k8s_controller_req_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-controller-req 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )
  # Check if iam-config unit has resources in state
  iam_config_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../iam-config 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null || true"
  )


  state_has_resources          = trimspace(local.state_check_cmd_output) != ""
  k8s_controller_req_has_state = trimspace(local.k8s_controller_req_state_check_output) != ""
  argocd_core_has_state        = trimspace(local.k8s_argocd_core_state_check_output) != ""
  iam_config_has_state         = trimspace(local.iam_config_state_check_output) != ""

  # Determine if after-hooks should run based on state and enable flags
  # Hook 1: Remove k8s-controller-req state if it has state but ArgoCD is disabled
  # Hook 2: Remove k8s-argocd-core state if it has state but ArgoCD is disabled
  # Hook 3: Destroy iam-config if it has state but ArgoCD is disabled
  # Hook 4 & 5: Reapply cluster and VPC if any of the above hooks ran
  should_remove_controller_req_state = !values.enable_argocd && local.k8s_controller_req_has_state
  should_remove_argocd_core_state    = !values.enable_argocd && local.argocd_core_has_state
  should_destroy_iam_config          = !values.enable_argocd && local.iam_config_has_state
  should_reapply_infrastructure      = local.should_remove_controller_req_state || local.should_remove_argocd_core_state || local.should_destroy_iam_config

  # Enablement logic
  need_k8s_providers = local.state_has_resources || values.enable_argocd || local.argocd_core_has_state
  create_resources   = values.enable_argocd

  # Spokes list for modules (simplified - IAM data will be passed separately)
  spokes_list = [
    for spoke_alias, spoke_config in values.spokes :
    {
      alias            = spoke_alias
      name             = lookup(spoke_config, "name", spoke_alias)
      cluster_endpoint = lookup(spoke_config, "cluster_endpoint", "")
      cluster_ca_cert  = lookup(spoke_config, "cluster_ca_cert", "")
      region           = lookup(spoke_config, "region", values.region)
      account_id       = lookup(spoke_config, "account_id", "")
      provider         = spoke_config.provider
      namespace        = try(spoke_config.namespace, "${spoke_alias}-infrastructure")
    }
  ]
}

###############################################################################
# Dependencies
###############################################################################
# Dependency: Spoke Infrastructure (must exist before ArgoCD)
dependency "k8s_argocd_core" {
  config_path = "../k8s-argocd-core"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {}
}


# Dependency: Spoke-IAM Unit
dependency "spoke_iam" {
  config_path = "../iam-config"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    spoke_identities = {
      "mock-spoke" = {
        account_id       = "123456789012"
        subscription_id  = ""
        tenant_id        = ""
        project_id       = ""
        project_number   = ""
        region           = "us-east-1"
        controllers      = {
          for controller_name, config in try(values.all_configs, {}) :
          controller_name => {
            role_arn                = "arn:aws:iam::987654321098:role/mock-spoke-${controller_name}-role"
            role_name               = "mock-spoke-${controller_name}-role"
            identity_id             = ""
            identity_name           = ""
            client_id               = ""
            service_account_email   = ""
            service_account_name    = ""
            service_name            = controller_name
            policy_source           = "spoke_created"
          }
        }
      }
    }
  }
}

# Dependency: K8s Cluster Unit
dependency "k8s_cluster" {
  config_path = "../k8s-cluster"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    cluster_name     = "mock-csoc-cluster"
    cluster_endpoint = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURLVENDQWhHZ0F3SUJBZ0lJWlNDNlV0SVZKNll3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TlRBMU1EVXdNVEE0TXpWYUZ3MHlOakExTURVd01URXpNemxhTUR3eApIekFkQmdOVkJBb1RGbXQxWW1WaFpHMDZZMngxYzNSbGNpMWhaRzFwYm5NeEdUQVhCZ05WQkFNVEVHdDFZbVZ5CmJtVjBaWE10WVdSdGFXNHdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEUmdqTzkKRGQ3RGtyYW9nclBGOGs3SEdWdStDNnBPcWxYU3VvNGRGdi9GamtJMzk5NDR6ajY5RHM1KzZGZWt4ZlBTWWhpYgpIclRablNycHlpUmpyaGhydjZDYkhHWlU4ay8rR0t2MFFFMHk3TXk3d3BxOWtIbXpJTUlXTVJoWUM4L3BnSTRTCmlYZEUzQWpJSUpPRUszR0NDdTFDQ1Vla0JuaS93elRQdTFyZWUxRnlZQXNvVUNKeHJJVDNDY2tDTHpHWGkxK0gKSVdOdWtMdSt4Skl0WUdLY3JvUHRReDNKSnlZSFUxbjBkdFQ2OXVROThHbWdGOFpHdmNJZTVvK0JlUUlLMS9JOAp1UHhBZS9QVUhyUFhxdVR6d1JiU1gwM1dNTE81aWdOSFNrVktOazJYb1FlWXh2eWZjdlVyZFpVOUdqWlZ5akMrCnQzUXFaVk9PSHZXY3Y4NVhBZ01CQUFHalZqQlVNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUsKQmdnckJnRUZCUWNEQWpBTUJnTlZIUk1CQWY4RUFqQUFNQjhHQTFVZEl3UVlNQmFBRks0NTVMQ21DcHF2YzdzaAo3UGlLYmVjbkNyYkpNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUJBUUJNSlRMcTA2TU9ZQ2U2cHJBZUZTNUpwNTB3CkNHSUZSK3NyaUhORHVGZWsxMEd3eDVITGd3WW1FVElKMkdNZiswazNrSHFEWkZ1ZkJLQTh3V2JtUzZEUE9Vb0sKWXRQOUVvUU81a2haQzBoUVg0YkFWOXJJMzNOamd0RGgxcVJHSTNIYUZudS9YdUJPMkt6WklvaVRxbWtOQTgzVQp0K0JOaUZ1enBwUHNsNDhtREdvNkVoUjg5aW1DMVVERVlsR00vR09XK1pOd1BSemh5dmRrajJOWE5EZkl2U0tYCmNTdWFyalFjUk12b0c4SlNWbDVoK3VCNXgwUGY1MWVXOG84OXo1NkIzalhJU0xxN08yWEZtUGVOOGlRd3dsK1EKZFg3S2hTTzV4akZIMGFoMVc4NVBnQ2FQQnA4QWh1YXZuYUYzZjZTL1IyNlRRTnM5N0s3V3Q5U1ovRGgrCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
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
    key     = "${values.csoc_alias}/units/spoke-infrastructure/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/spoke-infrastructure/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/spoke-infrastructure"
  }
}
EOF
    : ""
  )
}

###############################################################################
# Provider Configuration
###############################################################################
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.need_k8s_providers ? (
    values.csoc_provider == "aws" ? <<EOF
provider "kubernetes" {
  host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
  cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      "${try(dependency.k8s_cluster.outputs.cluster_name, "")}"
    ]
  }
}
EOF
    : values.csoc_provider == "azure" ? <<EOF
provider "kubernetes" {
  host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
  cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login", "spn",
      "--server-id", "6dae42f8-4368-4678-94ff-3960e28e3630",
      "--client-id", "${values.azure_client_id}",
      "--client-secret", "${values.azure_client_secret}",
      "--tenant-id", "${values.tenant_id}"
    ]
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
provider "kubernetes" {
  host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
  cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}
EOF
    : ""
  ) : <<EOF
# Providers disabled - no resources to manage
EOF
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  # Module control
  create = local.create_resources

  # Cluster info
  cluster_name = try(dependency.k8s_cluster.outputs.cluster_name, "")

  # Spokes configuration
  spokes         = local.spokes_list
  default_region = values.region

  # Spoke identity mappings from iam-config (complete spoke data with controllers)
  spoke_identity_mappings = try(dependency.spoke_iam.outputs.spoke_identities, {})

  # ArgoCD namespace for spokes charter configmap
  namespace = "argocd"

  # Labels
  labels = {
    cluster = try(dependency.k8s_cluster.outputs.cluster_name, "")
  }
}
