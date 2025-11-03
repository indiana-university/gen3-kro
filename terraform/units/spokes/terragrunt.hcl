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
    key     = "${values.csoc_alias}/units/spokes/terraform.tfstate"
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
    key                  = "${values.csoc_alias}/units/spokes/terraform.tfstate"
  }
}
EOF
    : values.csoc_provider == "gcp" ? <<EOF
terraform {
  backend "gcs" {
    bucket  = "${values.state_bucket}"
    prefix  = "${values.csoc_alias}/units/spokes"
  }
}
EOF
    : ""
  )
}

dependency "csoc" {
  config_path = values.csoc_path

  mock_outputs_allowed_terraform_commands = ["plan", "state", "init", "validate"]
  mock_outputs_merge_strategy_with_state  = "shallow"

  mock_outputs = values.csoc_provider == "aws" ? {
    cluster_name                       = "mock-cluster-name"
    cluster_endpoint                   = "https://mock-endpoint.eks.amazonaws.com"
    cluster_version                    = "1.31"
    cluster_arn                        = "arn:aws:eks:us-east-1:123456789012:cluster/mock-cluster"
    cluster_security_group_id          = "sg-mock123"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJME1EY3lOREUxTVRnek1Wb1hEVE0wTURjeU1qRTFNVGd6TVZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTG1lCjBGdW9xdVlDZjhIY0RlSjRyQmZBd0RBPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    oidc_provider                      = "oidc.eks.us-east-1.amazonaws.com/id/MOCK123"
    oidc_provider_arn                  = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/MOCK123"
    vpc_id                             = "vpc-mock123"
    private_subnets                    = ["subnet-mock1", "subnet-mock2"]
    public_subnets                     = ["subnet-mock3", "subnet-mock4"]
    addons_pod_identity_roles          = {}
    argocd_pod_identity_role_arn       = "arn:aws:iam::123456789012:role/mock-argocd-role"
    } : values.csoc_provider == "azure" ? {
    cluster_name                       = "mock-aks-cluster"
    cluster_endpoint                   = "https://mock-aks.azure.com"
    cluster_version                    = "1.31"
    cluster_arn                        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
    cluster_security_group_id          = "nsg-mock123"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJME1EY3lOREUxTVRnek1Wb1hEVE0wTURjeU1qRTFNVGd6TVZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTG1lCjBGdW9xdVlDZjhIY0RlSjRyQmZBd0RBPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    oidc_provider                      = "mock-aks.oidc.azure.com"
    oidc_provider_arn                  = "https://mock-aks.oidc.azure.com"
    vpc_id                             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    private_subnets                    = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-1"]
    public_subnets                     = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet-2"]
    addons_pod_identity_roles          = {}
    argocd_pod_identity_role_arn       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-argocd-identity"
    } : {
    cluster_name                       = "mock-gke-cluster"
    cluster_endpoint                   = "https://mock-gke.googleapis.com"
    cluster_version                    = "1.31"
    cluster_arn                        = "projects/mock-project/locations/us-central1/clusters/mock-gke-cluster"
    cluster_security_group_id          = "mock-firewall-123"
    cluster_certificate_authority_data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUMvakNDQWVhZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJME1EY3lOREUxTVRnek1Wb1hEVE0wTURjeU1qRTFNVGd6TVZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTG1lCjBGdW9xdVlDZjhIY0RlSjRyQmZBd0RBPT0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo="
    oidc_provider                      = "container.googleapis.com/v1/projects/mock-project/locations/us-central1/clusters/mock-gke-cluster"
    oidc_provider_arn                  = "https://container.googleapis.com/v1/projects/mock-project/locations/us-central1/clusters/mock-gke-cluster"
    vpc_id                             = "projects/mock-project/global/networks/mock-vpc"
    private_subnets                    = ["projects/mock-project/regions/us-central1/subnetworks/mock-subnet-1"]
    public_subnets                     = ["projects/mock-project/regions/us-central1/subnetworks/mock-subnet-2"]
    addons_pod_identity_roles          = {}
    argocd_pod_identity_role_arn       = "projects/mock-project/serviceAccounts/mock-argocd-sa@mock-project.iam.gserviceaccount.com"
  }
}

inputs = {
  csoc_provider = values.csoc_provider
  tags          = values.tags
  cluster_name  = values.cluster_name

  # VPC configuration
  enable_vpc          = values.enable_vpc
  vpc_name            = values.vpc_name
  vpc_cidr            = values.vpc_cidr
  enable_nat_gateway  = values.enable_nat_gateway
  single_nat_gateway  = values.single_nat_gateway
  vpc_tags            = values.vpc_tags
  public_subnet_tags  = values.public_subnet_tags
  private_subnet_tags = values.private_subnet_tags
  existing_vpc_id     = values.existing_vpc_id
  existing_subnet_ids = values.existing_subnet_ids
  # Explicit subnet configuration provided via module variables
  availability_zones   = values.availability_zones
  private_subnet_cidrs = values.private_subnet_cidrs
  public_subnet_cidrs  = values.public_subnet_cidrs

  # Kubernetes cluster configuration (cloud-agnostic)
  enable_k8s_cluster                       = values.enable_k8s_cluster
  cluster_version                          = values.cluster_version
  cluster_endpoint_public_access           = values.cluster_endpoint_public_access
  enable_cluster_creator_admin_permissions = values.enable_cluster_creator_admin_permissions
  k8s_cluster_tags                         = values.k8s_cluster_tags
  cluster_compute_config                   = values.cluster_compute_config

  # Addon configurations (structured from config.yaml)
  addon_configs = values.addon_configs

  # ArgoCD configuration
  enable_argocd    = values.enable_argocd
  argocd_namespace = values.argocd_namespace

  # Outputs directory
  outputs_dir = values.outputs_dir

  # Enable flags (computed)
  enable_multi_acct = values.enable_multi_acct

  # Spoke ARN inputs (loaded from JSON files or empty)
  spoke_arn_inputs = values.spoke_arn_inputs

  # IAM policies (loaded from repository files)
  spoke_iam_policies = values.spoke_iam_policies

  # CSOC outputs (from dependency) - use try() to handle when cluster is disabled
  csoc_cluster_name              = try(dependency.csoc.outputs.cluster_name, "")
  csoc_cluster_endpoint          = try(dependency.csoc.outputs.cluster_endpoint, "")
  csoc_cluster_version           = try(dependency.csoc.outputs.cluster_version, "")
  csoc_oidc_provider             = try(dependency.csoc.outputs.oidc_provider, "")
  csoc_oidc_provider_arn         = try(dependency.csoc.outputs.oidc_provider_arn, "")
  csoc_cluster_security_group_id = try(dependency.csoc.outputs.cluster_security_group_id, "")
  csoc_vpc_id                    = try(dependency.csoc.outputs.vpc_id, "")
  csoc_private_subnets           = try(dependency.csoc.outputs.private_subnets, [])
  csoc_public_subnets            = try(dependency.csoc.outputs.public_subnets, [])
  csoc_addons_pod_identity_roles = try(dependency.csoc.outputs.addons_pod_identity_roles, {})
  csoc_cluster_secret_annotations = try(dependency.csoc.outputs.argocd_cluster_secret_metadata.annotations, {})
}

generate "data" {
  path      = "data.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
# Data sources for csoc cluster information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
EOF
}

# Kubernetes provider using data sources for authentication
generate "spokes_kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents = (values.enable_k8s_cluster && values.csoc_provider == "aws" ? <<-EOF
# Data sources for EKS cluster authentication
data "aws_eks_cluster" "csoc_eks" {
  name = var.csoc_cluster_name
}

data "aws_eks_cluster_auth" "csoc_eks_auth" {
  name = var.csoc_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.csoc_eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.csoc_eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.csoc_eks_auth.token
}
EOF
    : values.enable_k8s_cluster && values.csoc_provider == "azure" ? <<-EOF
data "azurerm_kubernetes_cluster" "csoc_aks" {
  name                = var.csoc_cluster_name
  resource_group_name = var.csoc_resource_group_name
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.csoc_aks.kube_config.0.host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.csoc_aks.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.csoc_aks.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.csoc_aks.kube_config.0.client_key)
}
EOF
    : values.enable_k8s_cluster && values.csoc_provider == "gcp" ? <<-EOF
data "google_client_config" "default" {}

data "google_container_cluster" "csoc_gke" {
  name     = var.csoc_cluster_name
  location = var.csoc_cluster_location
}

provider "kubernetes" {
  host                   = "https://$${data.google_container_cluster.csoc_gke.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.csoc_gke.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}
EOF
  : "")
}

generate "spokes" {
  path      = "spokes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
# Spoke deployments - calls spoke combination modules for each spoke account

%{for spoke in values.spokes_config~}
module "spoke_${spoke.alias}" {
  source = "./combinations/spoke/${lookup(lookup(spoke, "provider", {}), "name", values.csoc_provider)}"

  # Spoke identification
  cluster_name            = var.cluster_name
  spoke_alias             = "${spoke.alias}"
  cloud_provider          = "${lookup(lookup(spoke, "provider", {}), "name", values.csoc_provider)}"
  tags                    = merge(var.tags, ${jsonencode(lookup(spoke, "tags", {}))})

  # CSOC pod identity ARNs
  csoc_pod_identity_arns  = var.csoc_addons_pod_identity_roles

  # Addon configurations with override_id support
  addon_configs           = ${jsonencode(lookup(spoke, "addon_configs", {}))}
  csoc_addon_configs      = var.addon_configs

  # IAM policies for this spoke
  spoke_iam_policies      = lookup(var.spoke_iam_policies, "${spoke.alias}", {})
  csoc_account_id         = data.aws_caller_identity.current.account_id

  # ArgoCD configuration
  enable_argocd           = var.enable_argocd
  enable_vpc              = var.enable_vpc
  enable_k8s_cluster      = var.enable_k8s_cluster
  argocd_namespace        = var.argocd_namespace

  # Outputs directory
  outputs_dir             = var.outputs_dir

  # Region and cluster info
  region                  = data.aws_region.current.id
  cluster_info            = {
    cluster_name              = var.csoc_cluster_name
    cluster_endpoint          = var.csoc_cluster_endpoint
    cluster_version           = var.csoc_cluster_version
    region                    = data.aws_region.current.id
    account_id                = data.aws_caller_identity.current.account_id
    oidc_provider             = var.csoc_oidc_provider
    oidc_provider_arn         = var.csoc_oidc_provider_arn
    cluster_security_group_id = var.csoc_cluster_security_group_id
    vpc_id                    = var.csoc_vpc_id
    private_subnets           = var.csoc_private_subnets
    public_subnets            = var.csoc_public_subnets
  }

  # GitOps context from CSOC cluster secret
  csoc_cluster_secret_annotations = var.csoc_cluster_secret_annotations
}

%{endfor~}

# Outputs for all spokes
%{for spoke in values.spokes_config~}
output "spoke_${spoke.alias}_service_roles" {
  description = "Service roles created for ${spoke.alias}"
  value       = module.spoke_${spoke.alias}.service_roles
}

output "spoke_${spoke.alias}_all_service_roles" {
  description = "All service roles (created + override) for ${spoke.alias}"
  value       = module.spoke_${spoke.alias}.all_service_roles
}

output "spoke_${spoke.alias}_configmap" {
  description = "ArgoCD ConfigMap info for ${spoke.alias}"
  value = {
    name      = module.spoke_${spoke.alias}.argocd_configmap_name
    namespace = module.spoke_${spoke.alias}.argocd_configmap_namespace
  }
}

%{endfor~}
EOF
}

# Generate variables file for spokes
generate "variables" {
  path      = "variables.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
variable "csoc_provider" {
  description = "Cloud provider for csoc cluster"
  type        = string
}

variable "spoke_iam_policies" {
  description = "Map of spoke IAM policies by spoke alias"
  type = map(map(string))
}

variable "addon_configs" {
  description = "CSOC addon configurations"
  type        = any
}

variable "enable_argocd" {
  description = "Whether ArgoCD is enabled in the CSOC cluster"
  type        = bool
  default     = false
}

variable "enable_vpc" {
  description = "Whether VPC is enabled in the CSOC cluster"
  type        = bool
  default     = true
}

variable "enable_k8s_cluster" {
  description = "Whether Kubernetes cluster is enabled in the CSOC cluster"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "ArgoCD namespace"
  type        = string
}

variable "outputs_dir" {
  description = "Directory to write output files"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "CSOC cluster name"
  type        = string
}

variable "tags" {
  description = "Common tags for spoke resources"
  type        = map(string)
}

variable "csoc_addons_pod_identity_roles" {
  description = "Map of csoc addon pod identity role ARNs"
  type        = map(string)
}

variable "csoc_cluster_version" {
  description = "CSOC EKS cluster version"
  type        = string
}

variable "csoc_oidc_provider" {
  description = "CSOC OIDC provider URL"
  type        = string
}

variable "csoc_cluster_security_group_id" {
  description = "CSOC cluster security group ID"
  type        = string
}

variable "csoc_vpc_id" {
  description = "CSOC VPC ID"
  type        = string
}

variable "csoc_private_subnets" {
  description = "CSOC private subnet IDs"
  type        = list(string)
}

variable "csoc_public_subnets" {
  description = "CSOC public subnet IDs"
  type        = list(string)
}

variable "csoc_cluster_name" {
  description = "CSOC cluster name"
  type        = string
}

variable "csoc_cluster_endpoint" {
  description = "CSOC cluster endpoint"
  type        = string
}

variable "csoc_oidc_provider_arn" {
  description = "CSOC OIDC provider ARN"
  type        = string
}

variable "csoc_cluster_secret_annotations" {
  description = "Annotations from the CSOC cluster secret for GitOps context"
  type        = map(string)
  default     = {}
}
EOF
}
