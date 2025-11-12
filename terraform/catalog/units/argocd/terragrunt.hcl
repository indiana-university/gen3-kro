###############################################################################
# ArgoCD Unit Terragrunt Configuration
###############################################################################

terraform {
  source = "${values.catalog_path}//modules"
}

###############################################################################
# Locals - Conditional Provider Logic
#
# Simplified ArgoCD Provider Configuration:
#
# Case 1: ArgoCD=false, State=empty
#   → Providers: disabled | Modules create: false
#
# Case 2: ArgoCD=false, State=has_resources
#   → Providers: enabled (for destroy) | Modules create: false
#   → NOTE: K8s cluster will be kept alive automatically by k8s-cluster unit
#
# Case 3: ArgoCD=true, State=empty
#   → Providers: enabled | Modules create: true (create ArgoCD)
#
# Case 4: ArgoCD=true, State=has_resources
#   → Providers: enabled | Modules create: true (reconcile/update)
#
###############################################################################
locals {
  # Enable flags
  enable_argocd = values.enable_argocd

  # Check if there are existing Kubernetes/Helm resources in state
  # This allows destroy operations to work even when enable_argocd = false
  # Initialize terraform first to ensure state can be read
  argocd_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && (terraform init -backend=false -input=false >/dev/null 2>&1 || true) && terraform state list 2>/dev/null | egrep '^kubernetes_|^helm_|^local_file\\.' || true"
  )) != ""

  # Provider enablement logic - simplified from 8 cases to 4 cases:
  # Enable providers when:
  # - ArgoCD resources exist in state (to allow destroy), OR
  # - ArgoCD is enabled (to allow create/update)
  # NOTE: We no longer check enable_k8s_cluster here because the k8s-cluster unit
  # will keep itself alive when ArgoCD is being destroyed
  need_k8s_providers = local.argocd_state_has_resources || local.enable_argocd

  # Module create flag logic:
  # Create resources only when ArgoCD is enabled
  create_resources = local.enable_argocd

  # Use cluster data from state if both argocd and cluster states have resources
  use_cluster_state_data = false
}
###############################################################################
# Dependencies
###############################################################################
# Dependency: CSOC Unit (cluster info, pod identities)
dependency "k8s_cluster" {
  config_path = "../k8s-cluster"

  # Skip outputs when destroying ArgoCD and no resources in state
  # When argocd_state_has_resources=true, we need cluster outputs for destroy
  skip_outputs = !local.enable_argocd && !local.argocd_state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
  mock_outputs = {
    cluster_name                        = "mock-csoc-cluster"
    cluster_endpoint                    = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURLVENDQWhHZ0F3SUJBZ0lJWlNDNlV0SVZKNll3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TlRBMU1EVXdNVEE0TXpWYUZ3MHlOakExTURVd01URXpNemxhTUR3eApIekFkQmdOVkJBb1RGbXQxWW1WaFpHMDZZMngxYzNSbGNpMWhaRzFwYm5NeEdUQVhCZ05WQkFNVEVHdDFZbVZ5CmJtVjBaWE10WVdSdGFXNHdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEUmdqTzkKRGQ3RGtyYW9nclBGOGs3SEdWdStDNnBPcWxYU3VvNGRGdi9GamtJMzk5NDR6ajY5RHM1KzZGZWt4ZlBTWWhpYgpIclRablNycHlpUmpyaGhydjZDYkhHWlU4ay8rR0t2MFFFMHk3TXk3d3BxOWtIbXpJTUlXTVJoWUM4L3BnSTRTCmlYZEUzQWpJSUpPRUszR0NDdTFDQ1Vla0JuaS93elRQdTFyZWUxRnlZQXNvVUNKeHJJVDNDY2tDTHpHWGkxK0gKSVdOdWtMdSt4Skl0WUdLY3JvUHRReDNKSnlZSFUxbjBkdFQ2OXVROThHbWdGOFpHdmNJZTVvK0JlUUlLMS9JOAp1UHhBZS9QVUhyUFhxdVR6d1JiU1gwM1dNTE81aWdOSFNrVktOazJYb1FlWXh2eWZjdlVyZFpVOUdqWlZ5akMrCnQzUXFaVk9PSHZXY3Y4NVhBZ01CQUFHalZqQlVNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUsKQmdnckJnRUZCUWNEQWpBTUJnTlZIUk1CQWY4RUFqQUFNQjhHQTFVZEl3UVlNQmFBRks0NTVMQ21DcHF2YzdzaAo3UGlLYmVjbkNyYkpNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUJBUUJNSlRMcTA2TU9ZQ2U2cHJBZUZTNUpwNTB3CkNHSUZSK3NyaUhORHVGZWsxMEd3eDVITGd3WW1FVElKMkdNZiswazNrSHFEWkZ1ZkJLQTh3V2JtUzZEUE9Vb0sKWXRQOUVvUU81a2haQzBoUVg0YkFWOXJJMzNOamd0RGgxcVJHSTNIYUZudS9YdUJPMkt6WklvaVRxbWtOQTgzVQp0K0JOaUZ1enBwUHNsNDhtREdvNkVoUjg5aW1DMVVERVlsR00vR09XK1pOd1BSemh5dmRrajJOWE5EZkl2U0tYCmNTdWFyalFjUk12b0c4SlNWbDVoK3VCNXgwUGY1MWVXOG84OXo1NkIzalhJU0xxN08yWEZtUGVOOGlRd3dsK1EKZFg3S2hTTzV4akZIMGFoMVc4NVBnQ2FQQnA4QWh1YXZuYUYzZjZTL1IyNlRRTnM5N0s3V3Q5U1ovRGgrCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
    region                              = values.region
    endpoint                            = "mock-endpoint.gke.googleapis.com"  # For GCP
    pod_identity_details = {
      mock_controller = {
        service_account_name      = "mock-sa"
        service_account_namespace = "mock-ns"
        role_arn                  = "arn:aws:iam::123456789012:role/mock-role"
      }
    }
    cluster_secret_annotations = {
      "kro.run/purpose" = "hub"
    }
  }
}

# Dependency: Spoke-IAM Unit (spoke roles, spoke cluster info)
dependency "spoke_iam" {
  config_path = "../iam-config"

  # Skip outputs when destroying ArgoCD and no resources in state
  skip_outputs = !local.enable_argocd && !local.argocd_state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers"]
  mock_outputs = {
    csoc_pod_identity_arns = {
      argocd = "arn:aws:iam::123456789012:role/csoc-pod-identity-argocd"
    }
    csoc_pod_identity_details = {
      argocd = {
        role_arn      = "arn:aws:iam::123456789012:role/csoc-pod-identity-argocd"
        role_name     = "mock-csoc-argocd-role"
        policy_arn    = "arn:aws:iam::123456789012:policy/mock-policy"
        service_name  = "argocd"
        policy_source = "loaded"
      }
    }
    spoke_service_roles_by_controller = {
      mock_controller = ["arn:aws:iam::987654321098:role/mock-spoke-role"]
    }
    spokes_all_service_roles = {
      spoke1 = {
        mock_controller = {
          role_arn     = "arn:aws:iam::987654321098:role/mock-spoke-role"
          service_name = "mock_controller"
          spoke_alias  = "spoke1"
          source       = "spoke_created"
        }
      }
    }
  }
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  create  = local.create_resources
  install = values.enable_argocd

  # Flag variables for validation (simplified - no longer need enable_k8s_cluster check)
  enable_argocd              = local.enable_argocd
  argocd_state_has_resources = local.argocd_state_has_resources

  # ArgoCD Helm configuration
  argocd = values.argocd_config

  # Cluster secret configuration
  cluster = merge(
    {
      name                 = try(dependency.k8s_cluster.outputs.cluster_name, "")
      endpoint             = try(dependency.k8s_cluster.outputs.cluster_endpoint, "")
      ca_cert              = try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")
      region               = values.region
      pod_identity_details = try(dependency.spoke_iam.outputs.csoc_pod_identity_details, {})
    },
    try(values.argocd_cluster, {}),
    {
      # Add structured annotations for ApplicationSet templates
      # These override/extend any annotations from values.argocd_cluster
      metadata = {
        annotations = merge(
          try(values.argocd_cluster.metadata.annotations, {}),
          {
            # GitOps context for CSOC addons ApplicationSet
            "csoc.kro.dev/gitops-context" = {
              aws_region = values.region
              region     = values.region
            }
            # Addons configuration (IAM roles from iam-config unit)
            "csoc.kro.dev/addons-config" = {
              for service_name, details in try(dependency.spoke_iam.outputs.csoc_pod_identity_details, {}) :
              service_name => {
                roleArn        = try(details.role_arn, "")
                serviceAccount = try(details.service_account_name, "${service_name}-sa")
                namespace      = try(details.service_account_namespace, "ack-system")
              }
            }
          }
        )
      }
    }
  )

  # Apps (bootstrap configuration)
  apps = values.argocd_bootstrap

  # Outputs directory
  outputs_dir = values.outputs_dir

  # Spokes configuration with account IDs and service roles from iam-config
  spokes = {
    for spoke_alias, spoke_config in values.spokes :
    spoke_alias => merge(
      spoke_config,
      {
        # Add account_id from spoke_all_service_roles if available
        account_id = try(
          # Try to get account_id from any service role ARN (extract from ARN)
          length(lookup(dependency.spoke_iam.outputs.spokes_all_service_roles, spoke_alias, {})) > 0 ?
          regex("arn:aws:iam::([0-9]+):role/.*", values(lookup(dependency.spoke_iam.outputs.spokes_all_service_roles, spoke_alias, {}))[0].role_arn)[0] :
          "",
          ""
        )
        # Add service roles map
        service_roles = try(dependency.spoke_iam.outputs.spokes_all_service_roles[spoke_alias], {})
        # Add namespace override if configured
        namespace = try(spoke_config.namespace, "${spoke_alias}-infrastructure")
      }
    )
  }

  # Pass the computed controller-to-spoke mappings for ConfigMap generation
  ack_controller_spoke_roles = {
    for controller_name, spoke_arns in try(dependency.spoke_iam.outputs.spoke_service_roles_by_controller, {}) :
    controller_name => {
      for spoke_alias, spoke_config in values.spokes :
      spoke_alias => {
        account_id = try(
          length(lookup(dependency.spoke_iam.outputs.spokes_all_service_roles, spoke_alias, {})) > 0 ?
          regex("arn:aws:iam::([0-9]+):role/.*", values(lookup(dependency.spoke_iam.outputs.spokes_all_service_roles, spoke_alias, {}))[0].role_arn)[0] :
          "",
          ""
        )
        role_arn = try(dependency.spoke_iam.outputs.spokes_all_service_roles[spoke_alias][controller_name].role_arn, "")
      }
      if try(dependency.spoke_iam.outputs.spokes_all_service_roles[spoke_alias][controller_name].role_arn, "") != ""
    }
  }

  debug_state_check = {
    argocd_state_has_resources = local.argocd_state_has_resources
    need_k8s_providers         = local.need_k8s_providers
    create_resources           = local.create_resources
    enable_argocd              = local.enable_argocd
  }

}

###############################################################################
# Generate Files
###############################################################################
# Generate variables for argocd and configmap modules
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
variable "create" {
  description = "Create terraform resources"
  type        = bool
}

variable "install" {
  description = "Install ArgoCD Helm chart"
  type        = bool
}

variable "enable_argocd" {
  description = "Whether ArgoCD is enabled"
  type        = bool
  default     = false
}

variable "argocd_state_has_resources" {
  description = "Whether ArgoCD state has existing resources"
  type        = bool
  default     = false
}

variable "argocd" {
  description = "ArgoCD Helm configuration"
  type        = any
}

variable "cluster" {
  description = "Cluster configuration"
  type        = any
}

variable "apps" {
  description = "ArgoCD apps/bootstrap configuration"
  type        = any
}

variable "outputs_dir" {
  description = "Directory to write output files"
  type        = string
}

variable "spokes" {
  description = "Spokes configuration"
  type        = any
}

variable "ack_controller_spoke_roles" {
  description = "Per-controller spoke role mappings for ACK ConfigMaps (data-driven from iam-config)"
  type = map(map(object({
    account_id = string
    role_arn   = string
  })))
  default = {}
}

# Optional Azure variables for kubelogin
variable "azure_client_id" {
  description = "Azure Client ID for kubelogin authentication"
  type        = string
  default     = ""
}

variable "azure_client_secret" {
  description = "Azure Client Secret for kubelogin authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure Tenant ID for kubelogin authentication"
  type        = string
  default     = ""
}

variable "debug_state_check" {
  description = "Debug information about state checks and provider enablement"
  type = object({
    argocd_state_has_resources = bool
    need_k8s_providers         = bool
    create_resources           = bool
    enable_argocd              = bool
  })
  default = {
    argocd_state_has_resources = false
    need_k8s_providers         = false
    create_resources           = false
    enable_argocd              = false
  }
}
EOF
}

# Generate ArgoCD module
generate "argocd_module" {
  path      = "argocd.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# ArgoCD Module
###############################################################################
module "argocd" {
  source = "./argocd"

  create      = var.create
  install     = var.install
  argocd      = var.argocd
  cluster     = var.cluster
  apps        = var.apps
  outputs_dir = var.outputs_dir
}

###############################################################################
# ACK ConfigMaps Module (Data-Driven)
# Dynamically creates ConfigMaps for all controllers from iam-config
###############################################################################

module "ack_configmaps" {
  source = "./aws-ack-configmaps"

  create                   = var.create
  cluster_name             = var.cluster.name
  controller_spoke_roles   = var.ack_controller_spoke_roles
}

# Debug output showing state check results
output "argocd_state_debug" {
  value = {
    state_checks = {
      argocd_has_resources = var.debug_state_check.argocd_state_has_resources
    }
    flags = {
      enable_argocd = var.debug_state_check.enable_argocd
    }
    computed = {
      need_k8s_providers = var.debug_state_check.need_k8s_providers
      create_resources   = var.debug_state_check.create_resources
    }
    case = (
      !var.debug_state_check.enable_argocd && !var.debug_state_check.argocd_state_has_resources ? "Case 1: ArgoCD disabled, no state" :
      !var.debug_state_check.enable_argocd && var.debug_state_check.argocd_state_has_resources ? "Case 2: ArgoCD disabled, has state (destroy)" :
      var.debug_state_check.enable_argocd && !var.debug_state_check.argocd_state_has_resources ? "Case 3: ArgoCD enabled, no state (create)" :
      var.debug_state_check.enable_argocd && var.debug_state_check.argocd_state_has_resources ? "Case 4: ArgoCD enabled, has state (update)" :
      "Unknown case"
    )
  }
}
EOF
}

# Generate data source to read cluster info from k8s-cluster state
# This is used when ArgoCD state has resources but we need cluster credentials for destroy
generate "cluster_data" {
  path      = "data_cluster.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.use_cluster_state_data ? (
    values.csoc_provider == "aws" ? <<-EOF
  data "terraform_remote_state" "cluster" {
    backend = "s3"
    config = {
      bucket = "${values.state_bucket}"
      key    = "${values.csoc_alias}/units/k8s-cluster/terraform.tfstate"
      region = "${values.region}"
    }
  }

  # Override cluster variable with data from state
  locals {
    cluster_from_state = {
      name     = try(data.terraform_remote_state.cluster.outputs.cluster_name, var.cluster.name)
      endpoint = try(data.terraform_remote_state.cluster.outputs.cluster_endpoint, var.cluster.endpoint)
      ca_cert  = try(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data, var.cluster.ca_cert)
      region   = try(data.terraform_remote_state.cluster.outputs.region, var.cluster.region)
    }
  }
EOF
    : values.csoc_provider == "azure" ? <<-EOF
  data "terraform_remote_state" "cluster" {
    backend = "azurerm"
    config = {
      storage_account_name = "${values.state_storage_account}"
      container_name       = "${values.state_container}"
      key                  = "${values.csoc_alias}/units/k8s-cluster/terraform.tfstate"
    }
  }

  # Override cluster variable with data from state
  locals {
    cluster_from_state = {
      name                 = try(data.terraform_remote_state.cluster.outputs.cluster_name, var.cluster.name)
      endpoint             = try(data.terraform_remote_state.cluster.outputs.cluster_endpoint, var.cluster.endpoint)
      ca_cert              = try(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data, var.cluster.ca_cert)
      region               = try(data.terraform_remote_state.cluster.outputs.region, var.cluster.region)
      azure_client_id      = var.azure_client_id
      tenant_id            = var.tenant_id
      azure_client_secret  = var.azure_client_secret
    }
  }
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
  data "terraform_remote_state" "cluster" {
    backend = "gcs"
    config = {
      bucket = "${values.state_bucket}"
      prefix = "${values.csoc_alias}/units/k8s-cluster"
    }
  }

  # Override cluster variable with data from state
  locals {
    cluster_from_state = {
      name     = try(data.terraform_remote_state.cluster.outputs.cluster_name, var.cluster.name)
      endpoint = try(data.terraform_remote_state.cluster.outputs.cluster_endpoint, var.cluster.endpoint)
      ca_cert  = try(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data, var.cluster.ca_cert)
      region   = try(data.terraform_remote_state.cluster.outputs.region, var.cluster.region)
    }
  }
EOF
    : ""
  ) : ""
}

# Generate backend configuration for ArgoCD state
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<EOF
  terraform {
    backend "s3" {
      bucket  = "${values.state_bucket}"
      key     = "${values.csoc_alias}/units/argocd/terraform.tfstate"
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
      key                  = "${values.csoc_alias}/units/argocd/terraform.tfstate"
    }
  }
EOF
    : values.csoc_provider == "gcp" ? <<EOF
  terraform {
    backend "gcs" {
      bucket  = "${values.state_bucket}"
      prefix  = "${values.csoc_alias}/units/argocd"
    }
  }
EOF
    : ""
  )
}

# Kubernetes provider for ArgoCD deployment
generate "kubernetes_provider" {
  path      = "provider_k8s.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local.need_k8s_providers ? <<-EOF
provider "kubernetes" {
  host                   = ${local.use_cluster_state_data ? "local.cluster_from_state.endpoint" : "var.cluster.endpoint"}
  cluster_ca_certificate = base64decode(${local.use_cluster_state_data ? "local.cluster_from_state.ca_cert" : "var.cluster.ca_cert"})

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "${values.csoc_provider == "aws" ? "aws" : values.csoc_provider == "azure" ? "kubelogin" : "gke-gcloud-auth-plugin"}"
    args = ${values.csoc_provider == "aws" ? jsonencode([
      "eks",
      "get-token",
      "--cluster-name",
      local.use_cluster_state_data ? "$${local.cluster_from_state.name}" : "$${var.cluster.name}",
      "--region",
      local.use_cluster_state_data ? "$${local.cluster_from_state.region}" : "$${var.cluster.region}"
    ]) : values.csoc_provider == "azure" ? jsonencode([
      "get-token",
      "--environment",
      "AzurePublicCloud",
      "--server-id",
      "6dae42f8-4368-4678-94ff-3960e28e3630",
      "--client-id",
      "$${var.azure_client_id}",
      "--tenant-id",
      "$${var.tenant_id}",
      "--login",
      "spn"
    ]) : []}
    ${values.csoc_provider == "azure" ? "env = {\n        AAD_SERVICE_PRINCIPAL_CLIENT_SECRET = var.azure_client_secret\n      }" : values.csoc_provider == "gcp" ? "env = {\n        USE_GKE_GCLOUD_AUTH_PLUGIN = \"True\"\n      }" : ""}
  }
}
EOF
    : ""
  )
}

# Helm provider for ArgoCD installation
generate "helm_provider" {
  path      = "provider_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents = local.need_k8s_providers ? (
    values.csoc_provider == "aws" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = ${local.use_cluster_state_data ? "local.cluster_from_state.endpoint" : "var.cluster.endpoint"}
      cluster_ca_certificate = base64decode(${local.use_cluster_state_data ? "local.cluster_from_state.ca_cert" : "var.cluster.ca_cert"})

      exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks",
          "get-token",
          "--cluster-name",
          ${local.use_cluster_state_data ? "local.cluster_from_state.name" : "var.cluster.name"},
          "--region",
          ${local.use_cluster_state_data ? "local.cluster_from_state.region" : "var.cluster.region"}
        ]
      }
    }
  }
EOF
    : values.csoc_provider == "azure" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = ${local.use_cluster_state_data ? "local.cluster_from_state.endpoint" : "var.cluster.endpoint"}
      cluster_ca_certificate = base64decode(${local.use_cluster_state_data ? "local.cluster_from_state.ca_cert" : "var.cluster.ca_cert"})

      exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "kubelogin"
        args = [
          "get-token",
          "--environment",
          "AzurePublicCloud",
          "--server-id",
          "6dae42f8-4368-4678-94ff-3960e28e3630",
          "--client-id",
          ${local.use_cluster_state_data ? "local.cluster_from_state.azure_client_id" : "var.azure_client_id"},
          "--tenant-id",
          ${local.use_cluster_state_data ? "local.cluster_from_state.tenant_id" : "var.tenant_id"},
          "--login",
          "spn"
        ]
        env = {
          AAD_SERVICE_PRINCIPAL_CLIENT_SECRET = ${local.use_cluster_state_data ? "local.cluster_from_state.azure_client_secret" : "var.azure_client_secret"}
        }
      }
    }
  }
EOF
    : values.csoc_provider == "gcp" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = ${local.use_cluster_state_data ? "local.cluster_from_state.endpoint" : "var.cluster.endpoint"}
      cluster_ca_certificate = base64decode(${local.use_cluster_state_data ? "local.cluster_from_state.ca_cert" : "var.cluster.ca_cert"})

      exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "gke-gcloud-auth-plugin"
        args        = []
        env = {
          USE_GKE_GCLOUD_AUTH_PLUGIN = "True"
        }
      }
    }
  }
EOF
    : ""
  ) : ""
}

###############################################################################
# End of File
###############################################################################
