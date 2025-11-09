###############################################################################
# ArgoCD Unit Terragrunt Configuration
###############################################################################

terraform {
  source = "${values.catalog_path}//modules"
}

###############################################################################
# Locals - Conditional Provider Logic
###############################################################################
locals {
  # Enable flag for ArgoCD installation
  enable_argocd = values.enable_argocd

  # Check if there are existing Kubernetes/Helm resources in state
  # This allows destroy operations to work even when enable_argocd = false
  argocd_state_has_resources = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && terraform state list 2>/dev/null | egrep '^kubernetes_|^helm_|^local_file\\.' || true"
  )) != ""

  # Check if k8s-cluster state has cluster resources
  # This indicates the cluster exists and we can read its data
  cluster_state_exists = trimspace(run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-cluster && terraform state list 2>/dev/null | egrep '^aws_eks_cluster\\.|^azurerm_kubernetes_cluster\\.|^google_container_cluster\\.|^module\\.eks\\.|^module\\.aks\\.|^module\\.gke\\.' || true"
  )) != ""

  # Need providers when: argocd enabled OR state has resources OR in migration mode
  need_k8s_providers = local.enable_argocd || local.argocd_state_has_resources || values.state_migration_mode

  # Use cluster data from state if both argocd and cluster states have resources
  use_cluster_state_data = local.argocd_state_has_resources && local.cluster_state_exists
}###############################################################################
# Dependencies
###############################################################################
# Dependency: CSOC Unit (cluster info, pod identities)
dependency "k8s_cluster" {
  config_path = "../k8s-cluster"

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
  create  = local.enable_argocd
  install = values.enable_argocd

  # ArgoCD Helm configuration
  argocd = values.argocd_config

  # Cluster secret configuration
  cluster = merge(
    {
      name                 = dependency.k8s_cluster.outputs.cluster_name
      endpoint             = dependency.k8s_cluster.outputs.cluster_endpoint
      ca_cert              = dependency.k8s_cluster.outputs.cluster_certificate_authority_data
      region               = values.region
      pod_identity_details = dependency.spoke_iam.outputs.csoc_pod_identity_details
    },
    try(values.argocd_cluster, {})
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
EOF
}

# Generate ArgoCD module
generate "argocd_module" {
  path      = "argocd.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
module "argocd" {
  source = "./argocd"

  create      = var.create
  install     = var.install
  argocd      = var.argocd
  cluster     = var.cluster
  apps        = var.apps
  outputs_dir = var.outputs_dir
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
# Generate Spoke ConfigMap Module
###############################################################################
generate "spoke_configmap" {
  path      = "spoke_configmap.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
###############################################################################
# Spoke Account Role Map ConfigMap
# Use argocd-configmap module to create spoke metadata ConfigMap
###############################################################################
module "spoke_configmap" {
  source = "./argocd-configmap"

  create           = var.create && var.spokes != null && length(var.spokes) > 0
  context          = "spokes"
  cluster_name     = var.cluster.name
  argocd_namespace = try(var.argocd.namespace, "argocd")
  pod_identities   = {}    # Not needed for spoke ConfigMap
  addon_configs    = {}    # Not needed for spoke ConfigMap
  cluster_info     = null  # Not needed for spoke ConfigMap
  gitops_context   = {}    # Not needed for spoke ConfigMap
  spokes           = var.spokes
  outputs_dir      = ""    # Don't write output file
}
EOF
}

###############################################################################
# End of File
###############################################################################
