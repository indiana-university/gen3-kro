# Hub Cluster Terraform Composition

This Terraform composition deploys a complete Gen3 KRO hub cluster with all necessary components for managing spoke clusters in a hub-spoke architecture.

## Overview

The hub composition orchestrates multiple Terraform modules to create:

- **VPC and Networking**: Private/public subnets, NAT gateways, security groups
- **EKS Cluster**: Kubernetes control plane and node groups
- **IAM Policies**: Loaded from `iam/` directory for ACK controllers and addons
- **Pod Identities**: IRSA-based authentication for Kubernetes workloads
- **Cross-Account Policies**: AssumeRole policies for multi-account scenarios
- **ArgoCD**: GitOps controller with bootstrap ApplicationSets
- **ConfigMaps**: Hub cluster configuration for ArgoCD consumption

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                      HUB COMPOSITION                       │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────┐      ┌─────────────┐      ┌──────────────┐ │
│  │   VPC    │─────▶│ EKS Cluster │─────▶│  ArgoCD      │ │
│  │  Module  │      │   Module    │      │  Module      │ │
│  └──────────┘      └─────────────┘      └──────────────┘ │
│                            │                     │         │
│                            ▼                     ▼         │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              IAM Policy Module                       │ │
│  │  (Loads policies from iam/<hub_alias>/)             │ │
│  └──────────────────────────────────────────────────────┘ │
│                            │                              │
│                            ▼                              │
│  ┌──────────────────────────────────────────────────────┐ │
│  │           Pod Identity Module (Hub)                  │ │
│  │  • ACK Controller Roles (EC2, EKS, IAM, RDS, etc.)  │ │
│  │  • Addon Roles (External Secrets, etc.)             │ │
│  └──────────────────────────────────────────────────────┘ │
│                            │                              │
│                            ▼                              │
│  ┌──────────────────────────────────────────────────────┐ │
│  │       Cross-Account Policy Module                    │ │
│  │  (AssumeRole policies for spoke accounts)           │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## Module Flow

### 1. VPC Module (`modules/vpc`)

Creates networking infrastructure:

```hcl
module "vpc" {
  source = "../../modules/vpc"

  create                 = var.enable_vpc
  vpc_name               = var.vpc_name
  vpc_cidr               = var.vpc_cidr
  cluster_name           = var.cluster_name
  availability_zones     = var.availability_zones
  private_subnet_cidrs   = var.private_subnet_cidrs
  public_subnet_cidrs    = var.public_subnet_cidrs
  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
}
```

**Outputs Used**:
- `vpc_id`: Passed to EKS module
- `private_subnets`: Passed to EKS module for node groups
- `public_subnets`: Available for load balancers

### 2. EKS Cluster Module (`modules/eks-cluster`)

Creates Kubernetes cluster:

```hcl
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  create                                   = var.enable_vpc && var.enable_eks_cluster
  cluster_name                             = var.cluster_name
  cluster_version                          = var.cluster_version
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  cluster_compute_config                   = var.cluster_compute_config
}
```

**Outputs Used**:
- `cluster_endpoint`: For kubeconfig generation
- `oidc_provider_arn`: For pod identity trust policies
- `cluster_name`: Referenced by pod identities

### 3. IAM Policy Module (`modules/iam-policy`)

Loads IAM policies from the `iam/` directory:

```hcl
module "iam_policies" {
  source = "../../modules/iam-policy"

  for_each = merge(
    # ACK services
    {
      for svc_name, svc_config in var.ack_configs :
      "ack-${svc_name}" => {
        service_type = "acks"
        service_name = svc_name
      }
      if var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
    },

    # Addons
    {
      for addon_name, addon_config in var.addon_configs :
      "${addon_name}" => {
        service_type = "addons"
        service_name = addon_name
      }
      if lookup(addon_config, "enable_pod_identity", false)
    }
  )

  service_type         = each.value.service_type
  service_name         = each.value.service_name
  context              = "hub"
  iam_policy_base_path = var.iam_base_path
  repo_root_path       = "${path.root}/../../../.."
}
```

**Policy Loading**:
- Loads from: `iam/gen3/<hub_alias>/<service_type>/<service_name>/`
- Supports: `internal-policy.json`, `override-policy-*.json`, `managed-policy-arns.txt`

### 4. Pod Identity Module (`modules/pod-identity`)

Creates IAM roles and pod identity associations for both ACK controllers and addons in a **single unified module call**:

```hcl
module "pod_identities" {
  source = "../../modules/pod-identity"

  # Unified for_each: merges ACK services and addons
  for_each = merge(
    # ACK services
    {
      for svc_name, svc_config in var.ack_configs :
      "ack-${svc_name}" => {
        service_type         = "acks"
        service_name         = svc_name
        namespace            = lookup(svc_config, "namespace", "ack-system")
        service_account      = lookup(svc_config, "service_account", "ack-${svc_name}-sa")
        custom_inline_policy = null
        enabled              = var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
      }
      if var.enable_ack && lookup(svc_config, "enable_pod_identity", true)
    },

    # Addons (external-secrets, ebs-csi, etc.)
    {
      for addon_name, addon_config in var.addon_configs :
      "${addon_name}" => {
        service_type         = "addons"
        service_name         = addon_name
        namespace            = lookup(addon_config, "namespace", "kube-system")
        service_account      = lookup(addon_config, "service_account", addon_name)
        custom_inline_policy = null
        enabled              = lookup(addon_config, "enable_pod_identity", false)
      }
      if lookup(addon_config, "enable_pod_identity", false)
    }
  )

  create          = var.enable_vpc && var.enable_eks_cluster && each.value.enabled
  cluster_name    = var.cluster_name
  service_type    = each.value.service_type
  service_name    = each.value.service_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  context         = "hub"

  # Use policies loaded by iam_policies module
  loaded_inline_policy_document    = try(module.iam_policies[each.key].inline_policy_document, null)
  loaded_override_policy_documents = try(module.iam_policies[each.key].override_policy_documents, [])
  loaded_managed_policy_arns       = try(module.iam_policies[each.key].managed_policy_arns, {})
  has_loaded_inline_policy         = try(module.iam_policies[each.key].has_inline_policy, false)

  # Custom inline policy (used only when no loaded policy exists)
  custom_inline_policy = each.value.custom_inline_policy
}
```

**Key Points**:
- **Single module call** handles both ACK controllers and addons
- Pod identities are prefixed: `ack-<service>` for ACK, `<addon_name>` for addons
- Policies loaded from `iam/gen3/csoc/acks/` and `iam/gen3/csoc/addons/`
- Creates IAM role: `<cluster_name>-<service_type>-<service_name>`
- Creates pod identity association and annotates service account

### 5. Cross-Account Policy Module (`modules/cross-account-policy`)

Attaches AssumeRole policies for multi-account scenarios:

```hcl
module "cross_account_policy" {
  source = "../../modules/cross-account-policy"

  for_each = var.ack_configs

  create = var.enable_multi_acct &&
           var.enable_ack &&
           lookup(each.value, "enable_pod_identity", true) &&
           length(local.spoke_role_arns_by_controller[each.key]) > 0

  service_name              = each.key
  hub_pod_identity_role_arn = module.pod_identities["ack-${each.key}"].role_arn
  spoke_role_arns           = local.spoke_role_arns_by_controller[each.key]
}
```

**Purpose**: Allows hub ACK controllers to assume roles in spoke accounts

### 6. ArgoCD Module (`modules/argocd`)

Deploys ArgoCD and bootstrap ApplicationSet:

```hcl
module "argocd" {
  source = "../../modules/argocd"

  create = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd

  argocd      = local.argocd_config_enhanced
  install     = var.argocd_install
  cluster     = local.argocd_cluster_enhanced
  apps        = local.argocd_apps_enhanced
  outputs_dir = var.argocd_outputs_dir
}
```

**Deploys**:
- ArgoCD Helm chart (version configured in `argocd_config`)
- Cluster secret with annotations for Git repo, role ARNs, namespaces, and service accounts
- Bootstrap ApplicationSet (single YAML that syncs `bootstrap/` directory)

**Bootstrap ApplicationSet**:
The bootstrap ApplicationSet uses a directory generator to deploy all ApplicationSet files from `argocd/bootstrap/`:
- `hub-addons.yaml` - Hub cluster addons (Wave 0)
- `spoke-addons.yaml` - Spoke cluster addons (Wave 0)
- `graphs.yaml` - ResourceGraphDefinitions (Wave 1)
- `graph-instances.yaml` - Infrastructure instances (Wave 2)
- `app-instances.yaml` - Application workloads (Wave 3)

### 7. Hub ConfigMap Module (`modules/spokes-configmap`)

Creates ConfigMap with hub cluster configuration for ArgoCD ApplicationSets:

```hcl
module "hub_configmap" {
  source = "../../modules/spokes-configmap"

  create           = var.enable_vpc && var.enable_eks_cluster && var.enable_argocd
  cluster_name     = var.cluster_name
  argocd_namespace = var.argocd_namespace

  # Hub pod identities (ACK controllers + addons)
  pod_identities = {
    for k, v in module.pod_identities : k => {
      role_arn      = v.role_arn
      role_name     = v.role_name
      policy_arn    = v.policy_arn
      service_type  = v.service_type
      service_name  = v.service_name
      policy_source = "hub_internal"
    }
  }

  # Configuration maps
  ack_configs   = var.ack_configs
  addon_configs = var.addon_configs

  # Hub cluster information
  cluster_info = {
    cluster_name              = var.cluster_name
    cluster_endpoint          = module.eks_cluster.cluster_endpoint
    region                    = data.aws_region.current.id
    account_id                = data.aws_caller_identity.current.account_id
    cluster_version           = module.eks_cluster.cluster_version
    oidc_provider             = module.eks_cluster.oidc_provider
    oidc_provider_arn         = module.eks_cluster.oidc_provider_arn
    cluster_security_group_id = module.eks_cluster.cluster_security_group_id
    vpc_id                    = module.vpc.vpc_id
    private_subnets           = module.vpc.private_subnets
    public_subnets            = module.vpc.public_subnets
  }

  # GitOps context
  gitops_context = {
    hub_repo_url      = var.argocd_cluster.metadata.annotations.hub_repo_url
    hub_repo_revision = var.argocd_cluster.metadata.annotations.hub_repo_revision
    hub_repo_basepath = var.argocd_cluster.metadata.annotations.hub_repo_basepath
    aws_region        = data.aws_region.current.id
  }

  # No spokes in hub configmap (spokes manage their own)
  spokes = {}
}
```

**ConfigMap Name**: `<cluster_name>-argocd-settings`
**ConfigMap Data Keys**:
- `ack.yaml` - ACK controller configurations
- `addons.yaml` - Addon configurations
- `cluster-info.yaml` - EKS cluster details
- `gitops-context.yaml` - Git repository information

## Input Variables

### Core Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `cluster_name` | `string` | EKS cluster name | Required |
| `cluster_version` | `string` | Kubernetes version | `"1.32"` |
| `enable_vpc` | `bool` | Create VPC | `true` |
| `enable_eks_cluster` | `bool` | Create EKS cluster | `true` |
| `enable_argocd` | `bool` | Install ArgoCD | `true` |
| `enable_ack` | `bool` | Enable ACK controllers | `true` |
| `enable_multi_acct` | `bool` | Enable cross-account policies | `false` |

### VPC Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `vpc_name` | `string` | VPC name | `""` |
| `vpc_cidr` | `string` | VPC CIDR block | `"10.0.0.0/16"` |
| `availability_zones` | `list(string)` | AZs for subnets | `["us-east-1a", "us-east-1b"]` |
| `private_subnet_cidrs` | `list(string)` | Private subnet CIDRs | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `public_subnet_cidrs` | `list(string)` | Public subnet CIDRs | `["10.0.101.0/24", "10.0.102.0/24"]` |
| `enable_nat_gateway` | `bool` | Enable NAT gateways | `true` |
| `single_nat_gateway` | `bool` | Use single NAT gateway | `true` |

### ACK Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `ack_configs` | `map(object)` | ACK controller configurations |

Example:
```hcl
ack_configs = {
  ec2 = {
    enable_pod_identity = true
    namespace           = "ack-system"
    service_account     = "ack-ec2-sa"
  }
  eks = {
    enable_pod_identity = true
    namespace           = "ack-system"
    service_account     = "ack-eks-sa"
  }
}
```

### Addon Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `addon_configs` | `map(object)` | Platform addon configurations |

Example:
```hcl
addon_configs = {
  external-secrets = {
    enable_pod_identity = true
    namespace           = "external-secrets-system"
    service_account     = "external-secrets"
  }
}
```

### IAM Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `iam_base_path` | `string` | Base path in iam/ directory | `"gen3"` |
| `iam_repo_root` | `string` | Repository root path | Auto-detected |

### ArgoCD Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `argocd_namespace` | `string` | ArgoCD namespace | `"argocd"` |
| `argocd_install` | `bool` | Install ArgoCD Helm chart | `true` |
| `argocd_config` | `object` | ArgoCD Helm values | See `variables.tf` |
| `argocd_cluster` | `object` | Cluster secret configuration | See `variables.tf` |
| `argocd_apps` | `map(string)` | ApplicationSet YAMLs | `{}` |

### Spoke ARN Inputs (Multi-Account)

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `spoke_arn_inputs` | `map(map(object))` | Spoke role ARNs by controller | `{}` |

Example:
```hcl
spoke_arn_inputs = {
  spoke1 = {
    ec2 = { role_arn = "arn:aws:iam::111111111111:role/spoke1-ec2" }
    eks = { role_arn = "arn:aws:iam::111111111111:role/spoke1-eks" }
  }
}
```

## Outputs

### VPC Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `private_subnets` | Private subnet IDs |
| `public_subnets` | Public subnet IDs |

### EKS Outputs

| Output | Description |
|--------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | EKS API server endpoint |
| `cluster_version` | Kubernetes version |
| `oidc_provider` | OIDC provider URL |
| `oidc_provider_arn` | OIDC provider ARN |

### Pod Identity Outputs

| Output | Description |
|--------|-------------|
| `pod_identities` | Map of all pod identity role ARNs |
| `ack_role_arns` | ACK controller role ARNs |
| `addon_role_arns` | Addon role ARNs |

### ArgoCD Outputs

| Output | Description |
|--------|-------------|
| `argocd_namespace` | ArgoCD namespace |
| `argocd_server_url` | ArgoCD server URL |

## Usage Example

### Terragrunt Configuration

```hcl
# live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl

terraform {
  source = "../../../../terraform/combinations/hub"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  # Core
  cluster_name    = "gen3-kro-hub"
  cluster_version = "1.32"

  # VPC
  enable_vpc            = true
  vpc_name              = "gen3-kro-hub-vpc"
  vpc_cidr              = "10.0.0.0/16"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24"]

  # EKS
  enable_eks_cluster = true
  cluster_compute_config = {
    min_size     = 2
    max_size     = 10
    desired_size = 3
    instance_types = ["t3.large"]
  }

  # ACK Controllers
  enable_ack = true
  ack_configs = {
    ec2 = {
      enable_pod_identity = true
      namespace           = "ack-system"
      service_account     = "ack-ec2-sa"
    }
    eks = {
      enable_pod_identity = true
      namespace           = "ack-system"
      service_account     = "ack-eks-sa"
    }
    iam = {
      enable_pod_identity = true
      namespace           = "ack-system"
      service_account     = "ack-iam-sa"
    }
  }

  # Addons
  addon_configs = {
    external-secrets = {
      enable_pod_identity = true
      namespace           = "external-secrets-system"
      service_account     = "external-secrets"
    }
  }

  # ArgoCD
  enable_argocd = true
  argocd_cluster = {
    metadata = {
      annotations = {
        hub_repo_url      = "https://github.com/indiana-university/gen3-kro.git"
        hub_repo_revision = "main"
        hub_repo_basepath = "argocd"
      }
    }
  }

  # IAM
  iam_base_path = "gen3"

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "Gen3-KRO"
  }
}
```

## Deployment Process

### 1. Initialize

```bash
cd live/aws/us-east-1/gen3-kro-hub
terragrunt init
```

### 2. Plan

```bash
terragrunt plan
```

Review the plan to ensure:
- VPC and subnets will be created (if `enable_vpc = true`)
- EKS cluster configuration is correct
- IAM policies are loaded from `iam/gen3/<hub_alias>/` paths
- Pod identities will be created for all ACK controllers and addons with `enable_pod_identity = true`
- ArgoCD will be installed with bootstrap ApplicationSet

### 3. Apply

```bash
terragrunt apply
```

Deployment takes ~20-30 minutes:
- VPC creation: ~2 minutes
- EKS cluster: ~15-20 minutes
- IAM policies loading: ~30 seconds
- Pod identities creation: ~2-3 minutes
- ArgoCD installation: ~3-5 minutes
- ConfigMap creation: ~10 seconds

### 4. Verify

```bash
# Connect to cluster
aws eks update-kubeconfig --name gen3-kro-hub --region us-east-1

# Check nodes
kubectl get nodes

# Check ArgoCD installation
kubectl get pods -n argocd
kubectl get applicationsets -n argocd

# Verify bootstrap ApplicationSet created child ApplicationSets
kubectl get applicationsets -n argocd
# Should show: bootstrap, hub-addons, spoke-addons, graphs, graph-instances, app-instances

# Check ArgoCD applications being synced
kubectl get applications -n argocd

# Check hub ConfigMap
kubectl get configmap <cluster-name>-argocd-settings -n argocd -o yaml

# Check pod identities (service accounts)
kubectl get sa -A | grep -E "ack-|external-secrets"

# Verify pod identity annotations
kubectl describe sa ack-ec2-controller -n ack-system
# Should show eks.amazonaws.com/role-arn annotation
```

## Conditional Deployment

### Deploy without VPC (Use existing)

```hcl
inputs = {
  enable_vpc         = false
  existing_vpc_id    = "vpc-xxxxxxxxx"
  existing_subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
}
```

### Deploy without ArgoCD

```hcl
inputs = {
  enable_argocd = false
}
```

### Multi-Account with Spoke ARNs

```hcl
inputs = {
  enable_multi_acct = true
  spoke_arn_inputs = {
    spoke1 = {
      ec2 = { role_arn = "arn:aws:iam::111111111111:role/spoke1-ec2" }
      eks = { role_arn = "arn:aws:iam::111111111111:role/spoke1-eks" }
    }
  }
}
```

## Maintenance

### Update ACK Controllers

Add or remove controllers in `ack_configs`:

```hcl
ack_configs = {
  # Add new controller
  s3 = {
    enable_pod_identity = true
    namespace           = "ack-system"
    service_account     = "ack-s3-sa"
  }
}
```

Ensure IAM policy exists: `iam/gen3/csoc/acks/s3/internal-policy.json`

### Update Cluster Version

```hcl
inputs = {
  cluster_version = "1.33"
}
```

Run `terragrunt apply` to upgrade the control plane and node groups.

### Destroy

```bash
# Delete ArgoCD applications first
kubectl delete applications --all -n argocd

# Destroy infrastructure
terragrunt destroy
```

## Troubleshooting

### Pod identity not working

**Symptom**: Pods cannot access AWS resources

**Check**:
```bash
kubectl describe sa <service-account> -n <namespace>
# Verify eks.amazonaws.com/role-arn annotation is present
```

**Solution**: Ensure IAM policy exists and pod identity module created the role

### ArgoCD not syncing

**Symptom**: Applications stuck in "OutOfSync" state

**Check**:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

**Solution**: Verify Git repository URL and credentials in cluster secret annotations

### Cross-account policy not working

**Symptom**: Hub ACK controller cannot manage resources in spoke account

**Check**:
```bash
# Verify cross-account policy attached
aws iam list-attached-role-policies --role-name gen3-kro-hub-ec2
```

**Solution**: Ensure `spoke_arn_inputs` contains correct spoke role ARNs

## See Also

- [Spoke Composition](../spoke/README.md)
- [Terraform Modules](../../modules/README.md)
- [ArgoCD Configuration](../../../argocd/README.md)
- [Terragrunt Deployment Guide](../../../docs/setup-terragrunt.md)
