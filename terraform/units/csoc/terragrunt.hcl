terraform {
  source = "${values.catalog_path}//."
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    values.csoc_provider == "aws" ? <<EOF
terraform {
  backend "s3" {
    bucket  = "${values.state_bucket}"
    key     = "${values.csoc_alias}/units/csoc/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/csoc/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/csoc"
  }
}
EOF
    : ""
  )
}

inputs = {
  catalog_path = values.catalog_path

  csoc_provider = values.csoc_provider
  tags          = values.tags
  cluster_name  = values.cluster_name
  csoc_alias    = values.csoc_alias

  enable_vpc           = values.enable_vpc
  vpc_name             = values.vpc_name
  vpc_cidr             = values.vpc_cidr
  enable_nat_gateway   = values.enable_nat_gateway
  single_nat_gateway   = values.single_nat_gateway
  vpc_tags             = values.vpc_tags
  public_subnet_tags   = values.public_subnet_tags
  private_subnet_tags  = values.private_subnet_tags
  existing_vpc_id      = values.existing_vpc_id
  existing_subnet_ids  = values.existing_subnet_ids
  availability_zones   = values.availability_zones
  private_subnet_cidrs = values.private_subnet_cidrs
  public_subnet_cidrs  = values.public_subnet_cidrs

  enable_k8s_cluster                       = values.enable_k8s_cluster
  cluster_version                          = values.cluster_version
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  k8s_cluster_tags                         = values.k8s_cluster_tags
  cluster_compute_config                   = values.cluster_compute_config

  addon_configs = values.addon_configs

  enable_multi_acct = values.enable_multi_acct

  spoke_arn_inputs = values.spoke_arn_inputs

  csoc_iam_policies = values.csoc_iam_policies

  enable_argocd      = values.enable_argocd
  argocd_config      = values.argocd_config
  argocd_install     = values.argocd_install
  argocd_cluster     = values.argocd_cluster
  argocd_outputs_dir = values.argocd_outputs_dir
  argocd_namespace   = values.argocd_namespace
}

# ArgoCD providers - use module outputs directly (no data sources needed in csoc)
generate "csoc_kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = (values.enable_k8s_cluster && values.csoc_provider == "aws" ? <<-EOF
provider "kubernetes" {
  host                   = module.csoc.cluster_endpoint
  cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", module.csoc.cluster_name,
      "--region", "${values.region}"${values.profile != "" ? format(",\n      \"--profile\", \"%s\"", values.profile) : ""}
    ]
  }
}
EOF
    : values.enable_k8s_cluster && values.csoc_provider == "azure" ? <<-EOF
provider "kubernetes" {
  host                   = module.csoc.cluster_endpoint
  cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)
  client_certificate     = base64decode(module.csoc.client_certificate)
  client_key             = base64decode(module.csoc.client_key)
}
EOF
    : values.enable_k8s_cluster && values.csoc_provider == "gcp" ? <<-EOF
provider "kubernetes" {
  host                   = "https://$${module.csoc.cluster_endpoint}"
  cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)
  token                  = data.google_client_config.default.access_token
}
EOF
  : "")
}

generate "csoc_helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = (values.enable_k8s_cluster && values.enable_argocd && values.csoc_provider == "aws" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = module.csoc.cluster_endpoint
      cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)

      exec = {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks", "get-token",
          "--cluster-name", module.csoc.cluster_name,
          "--region", "${values.region}"${values.profile != "" ? format(",\n        \"--profile\", \"%s\"", values.profile) : ""}
        ]
      }
    }
  }
EOF
    : values.enable_k8s_cluster && values.enable_argocd && values.csoc_provider == "azure" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = module.csoc.cluster_endpoint
      cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)
      client_certificate     = base64decode(module.csoc.client_certificate)
      client_key             = base64decode(module.csoc.client_key)
    }
  }
EOF
    : values.enable_k8s_cluster && values.enable_argocd && values.csoc_provider == "gcp" ? <<-EOF
  provider "helm" {
    kubernetes = {
      host                   = "https://$${module.csoc.cluster_endpoint}"
      cluster_ca_certificate = base64decode(module.csoc.cluster_certificate_authority_data)
      token                  = data.google_client_config.default.access_token
    }
  }
EOF
  : "")
}

# Generate variables.tf with all required variable declarations
generate "csoc_variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
  # Auto-generated variable declarations for csoc module inputs

  variable "csoc_provider" {
    type = string
  }

  variable "cluster_name" {
    type = string
  }

  variable "tags" {
    type = map(string)
  }

  variable "csoc_alias" {
    type = string
  }

  variable "enable_vpc" {
    type = bool
  }

  variable "vpc_name" {
    type = string
  }

  variable "vpc_cidr" {
    type = string
  }

  variable "enable_nat_gateway" {
    type = bool
  }

  variable "single_nat_gateway" {
    type = bool
  }

  variable "vpc_tags" {
    type = map(string)
  }

  variable "public_subnet_tags" {
    type = map(string)
  }

  variable "private_subnet_tags" {
    type = map(string)
  }

  variable "existing_vpc_id" {
    type = string
  }

  variable "existing_subnet_ids" {
    type = list(string)
  }

  variable "availability_zones" {
    type = list(string)
  }

  variable "private_subnet_cidrs" {
    type = list(string)
  }

  variable "public_subnet_cidrs" {
    type = list(string)
  }

  variable "enable_k8s_cluster" {
    type = bool
  }

  variable "cluster_version" {
    type = string
  }

  variable "cluster_endpoint_public_access" {
    type = bool
  }

  variable "enable_cluster_creator_admin_permissions" {
    type = bool
  }

  variable "cluster_compute_config" {
    type = any
  }

  variable "k8s_cluster_tags" {
    type = map(string)
  }

  variable "addon_configs" {
    type = any
  }

  variable "enable_multi_acct" {
    type = bool
  }

  variable "spoke_arn_inputs" {
    type = any
  }

  variable "enable_argocd" {
    type = bool
  }

  variable "argocd_namespace" {
    type = string
  }

  variable "argocd_config" {
    type = any
  }

  variable "argocd_install" {
    type = bool
  }

  variable "argocd_cluster" {
    type = any
  }

  variable "argocd_outputs_dir" {
    type = string
  }

  variable "csoc_iam_policies" {
    type = map(string)
  }
EOF
}


# Generate csoc.tf that calls the csoc combination module
generate "csoc_caller" {
  path      = "csoc.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF

  ###############################################################################
  # CSOC Module - Provider-specific combination
  ###############################################################################
  module "csoc" {
    source = "./combinations/csoc/${values.csoc_provider}"

    # Base configuration
    cluster_name = var.cluster_name
    tags         = var.tags
    csoc_alias   = var.csoc_alias

    # VPC variables
    enable_vpc                               = var.enable_vpc
    vpc_name                                 = var.vpc_name
    vpc_cidr                                 = var.vpc_cidr
    enable_nat_gateway                       = var.enable_nat_gateway
    single_nat_gateway                       = var.single_nat_gateway
    public_subnet_tags                       = var.public_subnet_tags
    private_subnet_tags                      = var.private_subnet_tags
    vpc_tags                                 = var.vpc_tags
    existing_vpc_id                          = var.existing_vpc_id
    existing_subnet_ids                      = var.existing_subnet_ids
    availability_zones                       = var.availability_zones
    private_subnet_cidrs                     = var.private_subnet_cidrs
    public_subnet_cidrs                      = var.public_subnet_cidrs

    # Kubernetes cluster variables (cloud-agnostic)
    enable_k8s_cluster                       = var.enable_k8s_cluster
    cluster_version                          = var.cluster_version
    cluster_endpoint_public_access           = var.cluster_endpoint_public_access
    enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
    cluster_compute_config                   = var.cluster_compute_config
    k8s_cluster_tags                         = var.k8s_cluster_tags

    # Addon configurations
    addon_configs                            = var.addon_configs
    enable_multi_acct                        = var.enable_multi_acct
    spoke_arn_inputs                         = var.spoke_arn_inputs

    # ArgoCD variables
    enable_argocd                            = var.enable_argocd
    argocd_namespace                         = var.argocd_namespace
    argocd_config                            = var.argocd_config
    argocd_install                           = var.argocd_install
    argocd_cluster                           = var.argocd_cluster
    argocd_outputs_dir                       = var.argocd_outputs_dir

    # IAM policies
    csoc_iam_policies                        = var.csoc_iam_policies
  }

EOF
}

# Generate outputs file for csoc unit
generate "outputs" {
  path      = "outputs.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
  ###############################################################################
  # CSOC Outputs - Exposed for Spokes Unit Dependency
  ###############################################################################

  output "cluster_name" {
    description = "Name of the EKS cluster"
    value       = module.csoc.cluster_name
  }

  output "cluster_endpoint" {
    description = "Endpoint for the EKS cluster"
    value       = module.csoc.cluster_endpoint
  }

  output "oidc_provider_arn" {
    description = "ARN of the OIDC provider for the EKS cluster"
    value       = module.csoc.oidc_provider_arn
  }

  output "oidc_provider" {
    description = "OIDC provider URL for the EKS cluster"
    value       = module.csoc.oidc_provider
  }

  output "cluster_version" {
    description = "Kubernetes version of the EKS cluster"
    value       = module.csoc.cluster_version
  }

  output "cluster_security_group_id" {
    description = "Security group ID of the EKS cluster"
    value       = module.csoc.cluster_security_group_id
  }

  output "vpc_id" {
    description = "VPC ID where the cluster is deployed"
    value       = module.csoc.vpc_id
  }

  output "private_subnets" {
    description = "List of private subnet IDs"
    value       = module.csoc.private_subnets
  }

  output "public_subnets" {
    description = "List of public subnet IDs"
    value       = module.csoc.public_subnets
  }

  output "addons_pod_identity_roles" {
    description = "Map of addon pod identity role ARNs"
    value       = module.csoc.addons_pod_identity_roles
  }
EOF
}
