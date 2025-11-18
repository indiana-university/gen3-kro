###############################################################################
# ArgoCD Core Unit Terragrunt Configuration
# Manages the ArgoCD deployment itself
###############################################################################

terraform {
  source = "${get_repo_root()}/${values.modules_path}/k8s-argocd-core"
}

###############################################################################
# Locals - Conditional Provider Logic
###############################################################################
locals {
  # Enable flags
  enable_argocd = values.enable_argocd

  # Check if there are existing resources in state
  state_check_cmd_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()} && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_|helm_|local_file\\.' || true"
  )
  # Check if k8s-spoke-req unit has resources in state
  k8s_spoke_req_state_check_output = run_cmd(
    "bash", "-c",
    "cd ${get_terragrunt_dir()}/../k8s-spoke-req 2>/dev/null && CACHE_DIR=$(find .terragrunt-cache -name 'backend.tf' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null) && [ -n \"$CACHE_DIR\" ] && cd \"$CACHE_DIR\" && terraform state list 2>/dev/null | egrep 'kubernetes_' || true"
  )

  state_has_resources       = trimspace(local.state_check_cmd_output) != ""
  k8s_spoke_req_has_state   = trimspace(local.k8s_spoke_req_state_check_output) != ""

  need_k8s_providers      = local.state_has_resources || values.enable_argocd
  create_resources        = local.k8s_spoke_req_has_state || values.enable_argocd
}

###############################################################################
# Dependencies
###############################################################################
# ArgoCD must wait for all infrastructure units to be created first
# This ensures namespaces, service accounts, and configmaps exist before ArgoCD deploys

# Dependency: Controller Infrastructure (must exist before ArgoCD)
dependency "controller_infrastructure" {
  config_path = "../k8s-controller-req"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {}
}

# Dependency: K8s Cluster Unit (cluster info, pod identities)
dependency "k8s_cluster" {
  config_path = "../k8s-cluster"

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    cluster_name                        = "mock-csoc-cluster"
    cluster_endpoint                    = "https://mock-endpoint.eks.amazonaws.com"
    cluster_certificate_authority_data  = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSURLVENDQWhHZ0F3SUJBZ0lJWlNDNlV0SVZKNll3RFFZSktvWklodmNOQVFFTEJRQXdGVEVUTUJFR0ExVUUKQXhNS2EzVmlaWEp1WlhSbGN6QWVGdzB5TlRBMU1EVXdNVEE0TXpWYUZ3MHlOakExTURVd01URXpNemxhTUR3eApIekFkQmdOVkJBb1RGbXQxWW1WaFpHMDZZMngxYzNSbGNpMWhaRzFwYm5NeEdUQVhCZ05WQkFNVEVHdDFZbVZ5CmJtVjBaWE10WVdSdGFXNHdnZ0VpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElCRHdBd2dnRUtBb0lCQVFEUmdqTzkKRGQ3RGtyYW9nclBGOGs3SEdWdStDNnBPcWxYU3VvNGRGdi9GamtJMzk5NDR6ajY5RHM1KzZGZWt4ZlBTWWhpYgpIclRablNycHlpUmpyaGhydjZDYkhHWlU4ay8rR0t2MFFFMHk3TXk3d3BxOWtIbXpJTUlXTVJoWUM4L3BnSTRTCmlYZEUzQWpJSUpPRUszR0NDdTFDQ1Vla0JuaS93elRQdTFyZWUxRnlZQXNvVUNKeHJJVDNDY2tDTHpHWGkxK0gKSVdOdWtMdSt4Skl0WUdLY3JvUHRReDNKSnlZSFUxbjBkdFQ2OXVROThHbWdGOFpHdmNJZTVvK0JlUUlLMS9JOAp1UHhBZS9QVUhyUFhxdVR6d1JiU1gwM1dNTE81aWdOSFNrVktOazJYb1FlWXh2eWZjdlVyZFpVOUdqWlZ5akMrCnQzUXFaVk9PSHZXY3Y4NVhBZ01CQUFHalZqQlVNQTRHQTFVZER3RUIvd1FFQXdJRm9EQVRCZ05WSFNVRUREQUsKQmdnckJnRUZCUWNEQWpBTUJnTlZIUk1CQWY4RUFqQUFNQjhHQTFVZEl3UVlNQmFBRks0NTVMQ21DcHF2YzdzaAo3UGlLYmVjbkNyYkpNQTBHQ1NxR1NJYjNEUUVCQ3dVQUE0SUJBUUJNSlRMcTA2TU9ZQ2U2cHJBZUZTNUpwNTB3CkNHSUZSK3NyaUhORHVGZWsxMEd3eDVITGd3WW1FVElKMkdNZiswazNrSHFEWkZ1ZkJLQTh3V2JtUzZEUE9Vb0sKWXRQOUVvUU81a2haQzBoUVg0YkFWOXJJMzNOamd0RGgxcVJHSTNIYUZudS9YdUJPMkt6WklvaVRxbWtOQTgzVQp0K0JOaUZ1enBwUHNsNDhtREdvNkVoUjg5aW1DMVVERVlsR00vR09XK1pOd1BSemh5dmRrajJOWE5EZkl2U0tYCmNTdWFyalFjUk12b0c4SlNWbDVoK3VCNXgwUGY1MWVXOG84OXo1NkIzalhJU0xxN08yWEZtUGVOOGlRd3dsK1EKZFg3S2hTTzV4akZIMGFoMVc4NVBnQ2FQQnA4QWh1YXZuYUYzZjZTL1IyNlRRTnM5N0s3V3Q5U1ovRGgrCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
    region                              = values.region
    endpoint                            = "mock-endpoint.gke.googleapis.com"
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

  skip_outputs = !values.enable_argocd && !local.state_has_resources

  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "providers", "destroy"]
  mock_outputs = {
    csoc_identities = {
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
    key     = "${values.csoc_alias}/units/k8s-argocd-core/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/k8s-argocd-core/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/k8s-argocd-core"
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

provider "helm" {
  kubernetes = {
    host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
    cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
    exec = {
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
}
EOF
    : values.csoc_provider == "azure" ? <<EOF
provider "azurerm" {
  features {}
  subscription_id = "${values.subscription_id}"
  tenant_id       = "${values.tenant_id}"
  client_id       = "${values.azure_client_id}"
  client_secret   = "${values.azure_client_secret}"
}

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

provider "helm" {
  kubernetes = {
    host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
    cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
    exec = {
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
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
provider "google" {
  project     = "${values.project_id}"
  region      = "${values.region}"
  credentials = "${values.credentials_file}"
}

provider "kubernetes" {
  host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
  cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

provider "helm" {
  kubernetes = {
    host                   = "${try(dependency.k8s_cluster.outputs.cluster_endpoint, "")}"
    cluster_ca_certificate = base64decode("${try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")}")
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
    }
  }
}
EOF
    : ""
  ) : <<EOF
# Providers disabled - no ArgoCD resources to manage
EOF
}

###############################################################################
# Inputs
###############################################################################
inputs = {
  # Module control
  create  = local.create_resources
  install = values.enable_argocd

  # ArgoCD configuration
  argocd = {
    namespace     = "argocd"
    chart         = "argo-cd"
    repository    = "https://argoproj.github.io/argo-helm"
    chart_version = "8.6.0"
    values        = [file("${get_repo_root()}/${values.modules_path}/k8s-argocd-core/bootstrap/argocd-initial-values.yaml")]
  }

  # Cluster secret configuration
  cluster = {
    name                 = try(dependency.k8s_cluster.outputs.cluster_name, "")
    endpoint             = try(dependency.k8s_cluster.outputs.cluster_endpoint, "")
    ca_cert              = try(dependency.k8s_cluster.outputs.cluster_certificate_authority_data, "")
    region               = values.region
    fleet_member         = "control-plane"
    metadata = {
      annotations = {
        # Repository Configuration
        repo_url       = values.csoc_repo_url
        repo_revision  = values.csoc_gitops_branch
        repo_basepath  = values.csoc_repo_basepath
        bootstrap_path = values.csoc_gitops_bootstrap_path

        # Cluster Information (use csoc_ prefix for hub cluster context)
        csoc_alias  = values.csoc_alias
        region      = values.region
      }
    }
  }

  # Apps (bootstrap configuration)
  apps = {
    bootstrap-applicationset = file("${get_repo_root()}/${values.modules_path}/k8s-argocd-core/bootstrap/applicationsets.yaml")
  }

  # Outputs directory
  outputs_dir = values.outputs_dir
}
