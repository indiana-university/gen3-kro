# Terraform Modules

This directory contains reusable Terraform modules for building the Gen3 KRO platform infrastructure. Each module is designed to be composable and can be used independently or as part of the hub/spoke combinations. The current module set provisions the AWS-based CSOC hub (VPC, EKS, IAM). Azure and Google Cloud resources are orchestrated through KRO ResourceGraphDefinitions and controller manifests in the `argocd/` tree.

## Module Overview

| Module | Purpose | Used By |
|--------|---------|---------|
| [argocd](#argocd) | Install and configure ArgoCD | Hub |
| [eks-cluster](#eks-cluster) | Provision EKS clusters | Hub |
| [vpc](#vpc) | Create VPC networking | Hub |
| [pod-identity](#pod-identity) | EKS Pod Identity (IRSA) for ACK/addons | Hub |
| [iam-policy](#iam-policy) | Load IAM policies from files | Hub, Spoke |
| [cross-account-policy](#cross-account-policy) | Cross-account AssumeRole policies (AWS) | Hub |
| [spoke-role](#spoke-role) | AWS IAM roles for spoke accounts (replaces ack-spoke-role) | Spoke |
| [spokes-configmap](#spokes-configmap) | ArgoCD configuration ConfigMaps | Hub, Spoke |

## Module Details

### argocd

**Purpose**: Deploy ArgoCD via Helm and configure cluster secrets and bootstrap ApplicationSets

**Key Features**:
- Helm chart installation
- Cluster secret creation with annotations
- Bootstrap ApplicationSet deployment
- App-of-apps pattern support

**Usage**:
```hcl
module "argocd" {
  source = "../../modules/argocd"

  create      = true
  install     = true
  argocd      = {
    namespace      = "argocd"
    chart_version  = "6.6.0"
    values         = [file("argocd-values.yaml")]
  }
  cluster     = {
    metadata = {
      annotations = {
        hub_repo_url = "https://github.com/org/repo.git"
      }
    }
  }
  apps        = {
    bootstrap = file("applicationsets.yaml")
  }
}
```

**Inputs**:
- `create`: Enable/disable module
- `install`: Install ArgoCD Helm chart
- `argocd`: Helm chart configuration
- `cluster`: Cluster secret configuration
- `apps`: ApplicationSet definitions

**Outputs**:
- `argocd_namespace`: ArgoCD namespace
- `cluster_secret_name`: Cluster secret name

---

### eks-cluster

**Purpose**: Provision AWS EKS clusters with node groups, OIDC provider, and pod identity support

**Key Features**:
- EKS control plane creation
- Managed node groups
- OIDC provider for IRSA
- Pod identity associations
- Cluster add-ons (EBS CSI, VPC CNI)

**Usage**:
```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  create                   = true
  cluster_name             = "my-cluster"
  cluster_version          = "1.32"
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  cluster_compute_config   = {
    min_size       = 2
    max_size       = 10
    desired_size   = 3
    instance_types = ["t3.large"]
  }
}
```

**Inputs**:
- `cluster_name`: EKS cluster name
- `cluster_version`: Kubernetes version
- `vpc_id`: VPC ID
- `subnet_ids`: Subnet IDs for node groups
- `cluster_compute_config`: Node group configuration

**Outputs**:
- `cluster_name`: Cluster name
- `cluster_endpoint`: API server endpoint
- `cluster_version`: Kubernetes version
- `oidc_provider`: OIDC provider URL
- `oidc_provider_arn`: OIDC provider ARN
- `cluster_security_group_id`: Cluster security group

---

### vpc

**Purpose**: Create AWS VPC with public/private subnets, NAT gateways, and route tables

**Key Features**:
- VPC with configurable CIDR
- Public and private subnets across AZs
- NAT gateways for private subnet internet access
- Internet gateway for public subnets
- Subnet tagging for EKS

**Usage**:
```hcl
module "vpc" {
  source = "../../modules/vpc"

  create                 = true
  vpc_name               = "my-vpc"
  vpc_cidr               = "10.0.0.0/16"
  cluster_name           = "my-cluster"
  availability_zones     = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs    = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway     = true
  single_nat_gateway     = true
}
```

**Inputs**:
- `vpc_name`: VPC name
- `vpc_cidr`: VPC CIDR block
- `cluster_name`: EKS cluster name (for tagging)
- `availability_zones`: AZs for subnets
- `private_subnet_cidrs`: Private subnet CIDRs
- `public_subnet_cidrs`: Public subnet CIDRs
- `enable_nat_gateway`: Enable NAT gateways
- `single_nat_gateway`: Use single NAT vs one per AZ

**Outputs**:
- `vpc_id`: VPC ID
- `private_subnets`: Private subnet IDs
- `public_subnets`: Public subnet IDs
- `nat_gateway_ids`: NAT gateway IDs

---

### pod-identity

**Purpose**: Create EKS Pod Identity (IRSA) associations with IAM roles

**Key Features**:
- IAM role creation
- Pod identity association
- Service account annotation
- Inline and managed policy support
- Cross-account policy support

**Usage**:
```hcl
# Typical usage with iam-policy module (recommended)
module "pod_identity" {
  source = "../../modules/pod-identity"

  create           = true
  cluster_name     = "my-cluster"
  service_type     = "acks"
  service_name     = "ec2"
  namespace        = "ack-system"
  service_account  = "ack-ec2-sa"
  context          = "hub"

  # Loaded policies from iam-policy module (preferred)
  loaded_inline_policy_document   = module.iam_policy["ack-ec2"].inline_policy_document
  loaded_override_policy_documents = module.iam_policy["ack-ec2"].override_policy_documents
  loaded_managed_policy_arns       = module.iam_policy["ack-ec2"].managed_policy_arns
  has_loaded_inline_policy         = module.iam_policy["ack-ec2"].has_inline_policy
}

# Alternative: Custom inline policy (used only when no loaded policies exist)
module "pod_identity_custom" {
  source = "../../modules/pod-identity"

  create           = true
  cluster_name     = "my-cluster"
  service_type     = "addons"
  service_name     = "argocd"
  namespace        = "argocd"
  service_account  = "argocd-application-controller"
  context          = "hub"

  # Custom policy used when no files exist in iam/ directory
  custom_inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]
        Resource = "*"
      }
    ]
  })
}
```

**Note**: The module prioritizes loaded policies over custom policies. If `has_loaded_inline_policy = true`, the custom policy is ignored.
```

**Inputs**:
- `cluster_name`: EKS cluster name
- `service_type`: Service type (acks, addons)
- `service_name`: Service name (ec2, eks, etc.)
- `namespace`: Kubernetes namespace
- `service_account`: Kubernetes service account
- `context`: Hub or spoke identifier
- `loaded_inline_policy_document`: Policy from iam-policy module
- `custom_inline_policy`: Custom policy JSON

**Outputs**:
- `role_arn`: IAM role ARN
- `role_name`: IAM role name
- `policy_arn`: Managed policy ARN (if created)
- `service_type`: Service type
- `service_name`: Service name

---

### iam-policy

**Purpose**: Load IAM policies from the `iam/` directory structure

**Key Features**:
- Loads internal, override, and managed policies
- Supports JSON policy files
- Supports managed policy ARN lists
- Context-aware path resolution (hub vs spoke)
- Policy aggregation and merging

**Directory Structure**:
```
iam/gen3/<context>/<service_type>/<service>/
├── internal-policy.json          # Main policy
├── override-policy-custom.json   # Additional policies (merged)
└── managed-policy-arns.txt       # AWS managed policy ARNs
```

**Usage**:
```hcl
module "iam_policy" {
  source = "../../modules/iam-policy"

  for_each = {
    ec2 = { service_type = "acks", service_name = "ec2" }
    eks = { service_type = "acks", service_name = "eks" }
  }

  service_type         = each.value.service_type
  service_name         = each.value.service_name
  context              = "hub"
  iam_policy_base_path = "gen3"
  repo_root_path       = "${path.root}/../../../.."
}
```

**Inputs**:
- `service_type`: Service type (acks, addons)
- `service_name`: Service name
- `context`: Hub, spoke-<alias>, or custom
- `iam_policy_base_path`: Base path in iam/ directory
- `repo_root_path`: Path to repository root

**Outputs**:
- `inline_policy_document`: Merged inline policy JSON
- `override_policy_documents`: List of override policies
- `managed_policy_arns`: Map of managed policy ARNs
- `has_inline_policy`: Boolean indicating presence of inline policy
- `has_managed_policies`: Boolean indicating presence of managed policies

---

### cross-account-policy

**Purpose**: Attach AssumeRole policies to hub pod identities for cross-account access

**Key Features**:
- Creates inline policy allowing AssumeRole
- Attaches to existing hub IAM role
- Supports multiple spoke role ARNs

**Usage**:
```hcl
module "cross_account_policy" {
  source = "../../modules/cross-account-policy"

  for_each = var.ack_configs

  create                    = var.enable_multi_acct
  service_name              = each.key
  hub_pod_identity_role_arn = module.pod_identity["ack-${each.key}"].role_arn
  spoke_role_arns           = [
    "arn:aws:iam::222222222222:role/spoke1-ec2",
    "arn:aws:iam::333333333333:role/spoke2-ec2"
  ]
}
```

**Inputs**:
- `service_name`: Service name (for policy name)
- `hub_pod_identity_role_arn`: Hub IAM role ARN
- `spoke_role_arns`: List of spoke role ARNs to assume

**Outputs**:
- `policy_name`: Policy name
- `policy_arn`: Policy ARN (if managed policy)

**Generated Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::222222222222:role/spoke1-ec2",
        "arn:aws:iam::333333333333:role/spoke2-ec2"
      ]
    }
  ]
}
```

---

### spoke-role

**Purpose**: Create IAM roles in spoke accounts with trust policies to hub

**Key Features**:
- IAM role creation
- Trust policy to hub pod identity
- Inline policy attachment
- Managed policy attachment

**Usage**:
```hcl
module "spoke_role" {
  source = "../../modules/spoke-role"

  for_each = local.services_needing_roles

  create                    = true
  service_type              = each.value.service_type
  cluster_name              = var.cluster_name
  service_name              = each.key
  spoke_alias               = var.spoke_alias
  hub_pod_identity_role_arn = each.value.hub_role_arn

  combined_policy_json = module.iam_policy[each.key].inline_policy_document
  policy_arns          = module.iam_policy[each.key].managed_policy_arns
  has_inline_policy    = module.iam_policy[each.key].has_inline_policy
}
```

**Inputs**:
- `service_type`: Service type
- `cluster_name`: Expected cluster name
- `service_name`: Service name
- `spoke_alias`: Spoke identifier
- `hub_pod_identity_role_arn`: Hub role ARN (for trust policy)
- `combined_policy_json`: Inline policy JSON
- `policy_arns`: Map of managed policy ARNs
- `has_inline_policy`: Boolean

**Outputs**:
- `role_arn`: IAM role ARN
- `role_name`: IAM role name

**Trust Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/hub-ack-ec2"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

---

### spokes-configmap

**Purpose**: Generate ConfigMaps with role information for ArgoCD generators

**Key Features**:
- YAML/JSON data formatting
- Role ARN aggregation
- Cluster metadata embedding
- GitOps context information

**Usage**:
```hcl
module "configmap" {
  source = "../../modules/spokes-configmap"

  create           = true
  cluster_name     = var.cluster_name
  argocd_namespace = "argocd"

  pod_identities = {
    ec2 = {
      role_arn      = "arn:aws:iam::123456789012:role/cluster-ec2"
      role_name     = "cluster-ec2"
      service_type  = "acks"
      service_name  = "ec2"
      policy_source = "hub_internal"
    }
  }

  ack_configs   = var.ack_configs
  addon_configs = var.addon_configs

  cluster_info = {
    cluster_endpoint = "https://xxx.eks.amazonaws.com"
    vpc_id           = "vpc-xxx"
    region           = "us-east-1"
  }

  gitops_context = {
    hub_repo_url = "https://github.com/org/repo.git"
    hub_repo_revision = "main"
  }
}
```

**Inputs**:
- `cluster_name`: Cluster name
- `argocd_namespace`: Namespace for ConfigMap
- `pod_identities`: Map of role information
- `ack_configs`: ACK configurations
- `addon_configs`: Addon configurations
- `cluster_info`: Cluster metadata
- `gitops_context`: Git repository information

**Outputs**:
- `configmap_name`: ConfigMap name
- `configmap_data`: ConfigMap data (for reference)

**Generated ConfigMap**:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-cluster-config
  namespace: argocd
data:
  cluster_name: my-cluster
  roles: |
    ec2:
      role_arn: arn:aws:iam::123456789012:role/cluster-ec2
      role_name: cluster-ec2
      service_type: acks
      policy_source: hub_internal
  cluster_info: |
    cluster_endpoint: https://xxx.eks.amazonaws.com
    vpc_id: vpc-xxx
    region: us-east-1
```

---

## Module Dependencies

```
┌─────────────┐
│     VPC     │
└──────┬──────┘
       │
       ↓
┌─────────────┐      ┌──────────────┐
│ EKS Cluster │      │  IAM Policy  │
└──────┬──────┘      └───────┬──────┘
       │                     │
       │    ┌────────────────┘
       │    │
       ↓    ↓
┌──────────────────┐       ┌────────────────┐
│  Pod Identity    │◀─────▶│  Spoke Role    │
└────────┬─────────┘       └────────────────┘
         │
         ↓
┌──────────────────────┐
│ Cross-Account Policy │
└──────────────────────┘
         │
         ↓
┌──────────────────────┐
│      ArgoCD          │
└──────────────────────┘
         │
         ↓
┌──────────────────────┐
│ Spokes ConfigMap     │
└──────────────────────┘
```

## Common Patterns

### Hub Cluster Deployment

```hcl
# 1. Create VPC
module "vpc" { ... }

# 2. Create EKS Cluster
module "eks_cluster" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
}

# 3. Load IAM Policies
module "iam_policies" { ... }

# 4. Create Pod Identities
module "pod_identities" {
  cluster_name                  = module.eks_cluster.cluster_name
  loaded_inline_policy_document = module.iam_policies[each.key].inline_policy_document
  depends_on                    = [module.eks_cluster, module.iam_policies]
}

# 5. Attach Cross-Account Policies
module "cross_account_policies" {
  hub_pod_identity_role_arn = module.pod_identities[each.key].role_arn
  depends_on                = [module.pod_identities]
}

# 6. Install ArgoCD
module "argocd" {
  depends_on = [module.eks_cluster]
}

# 7. Create Hub ConfigMap
module "hub_configmap" {
  pod_identities = module.pod_identities
  depends_on     = [module.argocd]
}
```

### Spoke IAM Deployment

```hcl
# 1. Load IAM Policies
module "iam_policies" { ... }

# 2. Create Spoke Roles
module "spoke_roles" {
  combined_policy_json = module.iam_policies[each.key].inline_policy_document
  depends_on           = [module.iam_policies]
}

# 3. Create Spoke ConfigMap
module "spoke_configmap" {
  pod_identities = module.spoke_roles
  depends_on     = [module.spoke_roles]
}
```

## Best Practices

### 1. Use `for_each` for Multiple Instances

```hcl
module "pod_identities" {
  source = "../../modules/pod-identity"

  for_each = {
    for k, v in var.ack_configs : k => v
    if lookup(v, "enable_pod_identity", true)
  }

  service_name = each.key
  # ...
}
```

### 2. Use `depends_on` for Ordering

```hcl
module "pod_identities" {
  # ...
  depends_on = [module.eks_cluster, module.iam_policies]
}
```

### 3. Pass Module Outputs Directly

```hcl
module "cross_account_policy" {
  hub_pod_identity_role_arn = module.pod_identities["ack-ec2"].role_arn
}
```

### 4. Use Conditional Creation

```hcl
module "vpc" {
  create = var.enable_vpc
  # ...
}
```

### 5. Aggregate Outputs with Locals

```hcl
locals {
  ack_role_arns = {
    for k, v in module.pod_identities :
    replace(k, "ack-", "") => v.role_arn
    if startswith(k, "ack-")
  }
}

output "ack_role_arns" {
  value = local.ack_role_arns
}
```

## Testing Modules

### 1. Validate Syntax

```bash
cd terraform/modules/<module-name>
terraform init
terraform validate
```

### 2. Plan with Mock Data

```bash
terraform plan -var-file=test.tfvars
```

### 3. Test in Isolation

Create a test wrapper:

```hcl
# test/main.tf
module "test" {
  source = "../"

  # Test inputs
  cluster_name = "test-cluster"
  # ...
}

output "test_outputs" {
  value = module.test
}
```

## Module Development Guidelines

### 1. Use `create` Variable

All modules should support conditional creation:

```hcl
variable "create" {
  description = "Whether to create resources"
  type        = bool
  default     = true
}

resource "aws_iam_role" "this" {
  count = var.create ? 1 : 0
  # ...
}
```

### 2. Document All Variables

```hcl
variable "cluster_name" {
  description = "Name of the EKS cluster. Used for resource naming and tagging."
  type        = string
}
```

### 3. Provide Sensible Defaults

```hcl
variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
  default     = "default"
}
```

### 4. Use `try()` for Optional Nested Values

```hcl
locals {
  namespace = try(var.config.namespace, "default")
}
```

### 5. Tag All Resources

```hcl
tags = merge(
  var.tags,
  {
    Module      = "pod-identity"
    ManagedBy   = "Terraform"
    ServiceName = var.service_name
  }
)
```

## See Also

- [Hub Composition](../combinations/hub/README.md)
- [Spoke Composition](../combinations/spoke/README.md)
- [Terragrunt Deployment Guide](../../docs/setup-terragrunt.md)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
