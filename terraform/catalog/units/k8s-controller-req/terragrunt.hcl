###############################################################################
# K8s Controller Requirements Unit Terragrunt Configuration
# Manages all controller namespaces, service accounts, and configmaps
# Cloud-agnostic unit for Kubernetes controller infrastructure
#
# Supports:
# - Addon controllers (external-secrets, cert-manager, kro, etc.)
# - ACK controllers (AWS Controllers for Kubernetes)
# - ASO controllers (Azure Service Operator)
# - GCC controllers (Google Config Connector)
# - Multi-cloud: Controllers from different providers on same cluster
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/k8s-controller-req"
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
  k8s_argocd_core_state_check = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-argocd-core 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_|helm_|local_file\\.' || true"
  )
  # Check if k8s-spoke-req unit has resources in state
  k8s_spoke_req_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-spoke-req 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )

  state_has_resources       = trimspace(local.state_check_cmd_output) != ""
  k8s_argocd_core_has_state = trimspace(local.k8s_argocd_core_state_check) != ""
  k8s_spoke_req_has_state   = trimspace(local.k8s_spoke_req_state_check_output) != ""

  has_dependent_resources = local.k8s_spoke_req_has_state || local.k8s_argocd_core_has_state
  need_k8s_providers      = local.state_has_resources || values.enable_argocd
  create_resources        = local.has_dependent_resources || values.enable_argocd
}

###############################################################################
# Dependencies
###############################################################################

# Dependency: K8s Cluster Unit
dependency "k8s_cluster" {
  config_path = "../k8s-cluster"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURLVENDQWhHZ0F3SUJBZ0lJWlNDNlV0SVZKNll3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TlRBMU1EVXdNVEE0TXpWYUZ3MHlOakExTURVd01URXpNemxhTUR3eApIekFkQmdOVkJBb1RGbXQxWW1WaFpHMDZZMngxYzNSbGNpMWhaRzFwYm5NeEdUQVhCZ05WQkFNVEVHdDFZbVZ5CmJtVjBaWE10WVdSdGFXNHdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEUmdqTzkKRGQ3RGtyYW9nclBGOGs3SEdWdStDNnBPcWxYU3VvNGRGdi9GamtJMzk5NDR6ajY5RHM1KzZGZWt4ZlBTWWhpYgpIclRablNycHlpUmpyaGhydjZDYkhHWlU4ay8rR0t2MFFFMHk3TXk3d3BxOWtIbXpJTUlXTVJoWUM4L3BnSTRTCmlYZEUzQWpJSUpPRUszR0NDdTFDQ1Vla0JuaS93elRQdTFyZWUxRnlZQXNvVUNKeHJJVDNDY2tDTHpHWGkxK0gKSVdOdWtMdSt4Skl0WUdLY3JvUHRReDNKSnlZSFUxbjBkdFQ2OXVROThHbWdGOFpHdmNJZTVvK0JlUUlLMS9JOAp1UHhBZS9QVUhyUFhxdVR6d1JiU1gwM1dNTE81aWdOSFNrVktOazJYb1FlWXh2eWZjdlVyZFpVOUdqWlZ5akMrCnQzUXFaVk9PSHZXY3Y4NVhBZ01CQUFHalZqQlVNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUsKQmdnckJnRUZCUWNEQWpBTUJnTlZIUk1CQWY4RUFqQUFNQjhHQTFVZEl3UVlNQmFBRks0NTVMQ21DcHF2YzdzaAo3UGlLYmVjbkNyYkpNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUJBUUJNSlRMcTA2TU9ZQ2U2cHJBZUZTNUpwNTB3CkNHSUZSK3NyaUhORHVGZWsxMEd3eDVITGd3WW1FVElKMkdNZiswazNrSHFEWkZ1ZkJLQTh3V2JtUzZEUE9Vb0sKWXRQOUVvUU81a2haQzBoUVg0YkFWOXJJMzNOamd0RGgxcVJHSTNIYUZudS9YdUJPMkt6WklvaVRxbWtOQTgzVQp0K0JOaUZ1enBwUHNsNDhtREdvNkVoUjg5aW1DMVVERVlsR00vR09XK1pOd1BSemh5dmRrajJOWE5EZkl2U0tYCmNTdWFyalFjUk12b0c4SlNWbDVoK3VCNXgwUGY1MWVXOG84OXo1NkIzalhJU0xxN08yWEZtUGVOOGlRd3dsK1EKZFg3S2hTTzV4akZIMGFoMVc4NVBnQ2FQQnA4QWh1YXZuYUYzZjZTL1IyNlRRTnM5N0s3V3Q5U1ovRGgrCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
  }
}

# Dependency: IAM Config Unit
dependency "iam_config" {
  config_path = "../iam-config"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    csoc_identities  = {
      "mock-controller" = {
        role_arn                = "arn:aws:iam::123456789012:role/mock-role"
        role_name               = "mock-role"
        policy_arn              = ""
        identity_id             = ""
        identity_name           = ""
        client_id               = ""
        service_account_email   = ""
        service_account_name    = ""
        service_name            = "mock-controller"
        k8s_service_account     = "mock-sa"
        k8s_namespace           = "mock-ns"
        policy_source           = "_default"
      }
    }
    spoke_identities = {
      "mock-spoke" = {
        account_id       = "123456789012"
        subscription_id  = ""
        tenant_id        = ""
        project_id       = ""
        project_number   = ""
        region           = "us-east-1"
        controllers      = {
          "mock-controller" = {
            role_arn                = "arn:aws:iam::987654321098:role/mock-spoke-role"
            role_name               = "mock-spoke-role"
            identity_id             = ""
            identity_name           = ""
            client_id               = ""
            service_account_email   = ""
            service_account_name    = ""
            service_name            = "mock-controller"
            policy_source           = "spoke_created"
          }
        }
      }
    }
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
    key     = "${values.csoc_alias}/units/controller-infrastructure/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/controller-infrastructure/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/controller-infrastructure"
  }
}
EOF
    : ""
  )
}

###############################################################################
# Provider Configuration - Cloud Agnostic
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

  # Unified controller configurations with cloud-specific identity information
  csoc_controller_configs = {
    for controller_name, config in try(values.all_configs, {}) :
    controller_name => {
      namespace       = config.namespace
      service_account = config.service_account
      # Try provider-specific fields: role_arn (AWS), identity_id (Azure), service_account_email (GCP)
      identity_arn    = try(
        dependency.iam_config.outputs.csoc_identities[controller_name].role_arn,          # AWS
        dependency.iam_config.outputs.csoc_identities[controller_name].identity_id,       # Azure
        dependency.iam_config.outputs.csoc_identities[controller_name].service_account_email, # GCP
        ""
      )
      identity_type   = values.csoc_provider # aws, azure, or gcp
      component_label = contains(keys(values.ack_configs), controller_name) ? "ack-controller" : (
        contains(keys(values.aso_configs), controller_name) ? "aso-controller" : (
          contains(keys(values.gcc_configs), controller_name) ? "gcc-controller" : "addon-controller"
        )
      )
    }
  }

  # Controller spoke roles mapping - transform spoke_identities to controller-first structure
  # Input:  spoke_alias -> { controllers: { controller_name -> identity_data } }
  # Output: controller_name -> spoke_alias -> identity_data
  controller_spoke_roles = {
    for controller_name in distinct(flatten([
      for spoke_alias, spoke_data in try(dependency.iam_config.outputs.spoke_identities, {}) :
      keys(try(spoke_data.controllers, {}))
    ])) :
    controller_name => {
      for spoke_alias, spoke_data in try(dependency.iam_config.outputs.spoke_identities, {}) :
      spoke_alias => {
        # AWS fields
        account_id = try(spoke_data.account_id, "")
        role_arn   = try(spoke_data.controllers[controller_name].role_arn, "")

        # Azure fields
        subscription_id = try(spoke_data.subscription_id, "")
        identity_id     = try(spoke_data.controllers[controller_name].identity_id, "")
        client_id       = try(spoke_data.controllers[controller_name].client_id, "")

        # GCP fields
        project_id            = try(spoke_data.project_id, "")
        service_account_email = try(spoke_data.controllers[controller_name].service_account_email, "")

        # Common fields
        region = try(spoke_data.region, "")
      }
      if contains(keys(try(spoke_data.controllers, {})), controller_name)
    }
  }

  # Labels
  labels = {}
}
