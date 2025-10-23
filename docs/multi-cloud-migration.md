# Multi-Cloud IAM and Infrastructure Migration

## Overview

This document describes the comprehensive restructuring of the Gen3 KRO platform to support multi-cloud deployments (AWS, Azure, GCP) with provider-specific IAM policy management and infrastructure modules.

## IAM Folder Structure

### New Provider-Based Structure

```
iam/
├── aws/
│   ├── _default/          # Default baseline policies (tracked in git)
│   │   ├── <addon>/
│   │   │   └── inline-policy.json
│   ├── csoc/              # Hub-specific policies (gitignored)
│   │   └── <addon>/
│   │       └── inline-policy.json
│   └── <spoke_alias>/     # Spoke-specific policies (gitignored)
│       └── <addon>/
│           └── inline-policy.json
├── azure/
│   ├── _default/
│   │   └── <addon>/
│   │       └── role-definition.json
│   ├── csoc/
│   │   └── <addon>/
│   │       └── role-definition.json
│   └── <spoke_alias>/
│       └── <addon>/
│           └── role-definition.json
└── gcp/
    ├── _default/
    │   └── <addon>/
    │       └── role.yaml
    ├── csoc/
    │   └── <addon>/
    │       └── role.yaml
    └── <spoke_alias>/
        └── <addon>/
            └── role.yaml
```

### Policy File Naming Conventions

- **AWS**: `inline-policy.json` - IAM inline policy documents
- **Azure**: `role-definition.json` - Azure role definitions
- **GCP**: `role.yaml` - GCP custom role definitions

### Migration from Legacy Structure

- Old: `iam/gen3/{context}/addons/{service}/source-policy-inline.json`
- New: `iam/{provider}/{context}/{service}/{policy-file}`

All existing AWS policies were migrated from `iam/gen3/` to `iam/aws/` with files renamed to `inline-policy.json`.

## Code Changes

### 1. IAM Policy Module (`terraform/modules/iam-policy`)

**Key Updates:**
- Added `provider` variable (aws/azure/gcp)
- Modified path resolution: `iam/{provider}/{context}/{service}/{policy-file}`
- Dynamic policy file naming based on provider
- Fallback logic: context-specific → _default

**Path Resolution Logic:**
```hcl
context_base_path = "iam/{provider}/{context}/{service}"
default_base_path = "iam/{provider}/_default/{service}"
```

### 2. Hub and Spoke Combinations

**AWS Combinations Updated:**
- `terraform/combinations/aws/hub/main.tf` - Added `provider = "aws"`
- `terraform/combinations/aws/spoke/main.tf` - Added `provider = var.provider`
- `terraform/combinations/aws/spoke/variables.tf` - Added provider variable

**Config Changes:**
- Added `provider` field to spoke configurations in `config.yaml`
- Terragrunt passes provider from config to modules

### 3. New Azure Modules

Created complete Azure infrastructure stack:

| Module | Purpose |
|--------|---------|
| `azure-resource-group` | Azure resource group management |
| `azure-vnet` | Virtual network and subnets |
| `azure-aks-cluster` | AKS cluster with workload identity |
| `azure-managed-identity` | Managed identities for workload identity |
| `azure-spoke-role` | Cross-subscription role assignments |

### 4. New GCP Modules

Created complete GCP infrastructure stack:

| Module | Purpose |
|--------|---------|
| `gcp-vpc` | VPC network and subnets |
| `gcp-gke-cluster` | GKE cluster with workload identity |
| `gcp-workload-identity` | Service accounts and workload identity bindings |
| `gcp-spoke-role` | Cross-project IAM bindings |

### 5. New Azure Combinations

- `terraform/combinations/azure/hub` - Hub infrastructure (RG, VNet, AKS, identities)
- `terraform/combinations/azure/spoke` - Spoke role assignments

### 6. New GCP Combinations

- `terraform/combinations/gcp/hub` - Hub infrastructure (VPC, GKE, workload identities)
- `terraform/combinations/gcp/spoke` - Spoke IAM bindings

## Configuration Changes

### Spoke Configuration (config.yaml)

```yaml
spokes:
  - alias: "spoke1"
    enabled: true
    provider: "aws"    # NEW: Specifies cloud provider
    region: "us-east-1"
    profile: "profile_name"
    addon_configs:
      external_secrets:
        enable_pod_identity: true  # AWS
        # or enable_workload_identity: true  # Azure/GCP
```

### Provider-Specific Fields

**AWS:**
- Uses `enable_pod_identity` for EKS Pod Identity
- IAM inline policies in JSON format

**Azure:**
- Uses `enable_workload_identity` for AKS Workload Identity
- Role definitions in JSON format
- Requires federated credentials

**GCP:**
- Uses `enable_workload_identity` for GKE Workload Identity
- Custom roles in YAML format
- Requires workload identity pool configuration

## Git Ignore Configuration

Updated `.gitignore` to track only _default baseline policies:

```gitignore
# Track only _default policies
/iam/aws/**
!/iam/aws/_default/**
/iam/azure/**
!/iam/azure/_default/**
/iam/gcp/**
!/iam/gcp/_default/**

# Legacy paths (deprecated)
/iam/gen3/
```

## Usage Examples

### AWS Hub Deployment

```hcl
module "hub" {
  source = "../../combinations/aws/hub"

  cluster_name = "gen3-kro-csoc"
  addon_configs = {
    external_secrets = {
      enable_pod_identity = true
      namespace           = "external-secrets"
      service_account     = "external-secrets"
    }
  }
}
```

### Azure Hub Deployment

```hcl
module "hub" {
  source = "../../combinations/azure/hub"

  cluster_name        = "gen3-kro-csoc"
  resource_group_name = "gen3-kro-rg"
  location            = "East US"

  addon_configs = {
    external_secrets = {
      enable_workload_identity = true
      namespace                = "external-secrets"
      service_account          = "external-secrets"
    }
  }
}
```

### GCP Hub Deployment

```hcl
module "hub" {
  source = "../../combinations/gcp/hub"

  project_id   = "my-gcp-project"
  cluster_name = "gen3-kro-csoc"
  region       = "us-central1"

  addon_configs = {
    external_secrets = {
      enable_workload_identity = true
      namespace                = "external-secrets"
      service_account          = "external-secrets"
    }
  }
}
```

## Migration Checklist

- [x] Restructure IAM folders by provider
- [x] Update iam-policy module for provider awareness
- [x] Add provider to spoke configuration
- [x] Create Azure modules (RG, VNet, AKS, Managed Identity, Spoke Role)
- [x] Create GCP modules (VPC, GKE, Workload Identity, Spoke Role)
- [x] Create Azure hub/spoke combinations
- [x] Create GCP hub/spoke combinations
- [x] Update .gitignore for new structure
- [ ] Test AWS deployment with new paths
- [ ] Test Azure deployment
- [ ] Test GCP deployment
- [ ] Update documentation
- [ ] Migrate existing deployments

## Key Architectural Decisions

1. **Provider-First Directory Structure**: Organizing by provider (`iam/{provider}/`) enables clear separation and provider-specific file formats.

2. **Fallback to _default**: Context-specific policies fall back to `_default` baseline, reducing duplication while allowing environment customization.

3. **Unified Module Interface**: The `iam-policy` module works across all providers by accepting a `provider` parameter and adjusting file paths/names accordingly.

4. **Separate Modules per Provider**: Rather than creating complex conditional logic in shared modules, provider-specific modules (e.g., `azure-aks-cluster` vs `eks-cluster`) keep code clean and maintainable.

5. **Workload Identity Naming**:
   - AWS: "Pod Identity" (EKS-specific)
   - Azure/GCP: "Workload Identity" (industry standard term)

## Breaking Changes

1. **IAM Policy Paths**: Old paths (`iam/gen3/`) deprecated in favor of `iam/{provider}/`
2. **Policy File Names**: `source-policy-inline.json` → provider-specific names
3. **Module Variables**: AWS spoke combination now requires `provider` variable
4. **Config Structure**: Spokes must specify `provider` field

## Compatibility Notes

- Legacy `iam/gen3/` directory remains for backward compatibility but is deprecated
- AWS deployments continue to work with provider automatically set to "aws"
- Existing AWS policy files were migrated and renamed
- `.gitignore` configured to ignore legacy paths

## Next Steps

1. **Testing**: Validate each provider's deployment independently
2. **Documentation**: Update user guides with provider-specific examples
3. **Policy Templates**: Create starter templates for common addons in all providers
4. **CI/CD**: Add validation for provider-specific policy file formats
5. **Migration Scripts**: Create helper scripts to migrate existing deployments

## Terragrunt Multi-Cloud Configuration

The `terragrunt.hcl` file has been updated to support multi-cloud deployments with provider-aware generation of Terraform sources, data sources, providers, and spoke modules.

### Dynamic Terraform Source Selection

The Terraform module source is now selected based on the hub provider:

```hcl
terraform {
  source = "${get_repo_root()}/terraform//combinations/${local.hub_provider}/hub"
}
```

This automatically selects:
- `terraform/combinations/aws/hub` for AWS
- `terraform/combinations/azure/hub` for Azure
- `terraform/combinations/gcp/hub` for GCP

### Provider-Specific Data Sources

Data sources are generated based on the hub provider:

**AWS:**
```hcl
data "aws_eks_cluster" "cluster" { ... }
data "aws_eks_cluster_auth" "cluster" { ... }
```

**Azure:**
```hcl
data "azurerm_kubernetes_cluster" "cluster" { ... }
```

**GCP:**
```hcl
data "google_container_cluster" "cluster" { ... }
```

### Provider-Specific Provider Configuration

Provider blocks are generated for the hub and all spokes based on their provider type:

**AWS Hub:**
```hcl
provider "aws" {
  region  = "us-east-1"
  profile = "profile-name"
  default_tags { tags = {...} }
}
```

**Azure Hub:**
```hcl
provider "azurerm" {
  features {}
  subscription_id = "..."
  tenant_id       = "..."
}
```

**GCP Hub:**
```hcl
provider "google" {
  project = "project-id"
  region  = "us-central1"
}
```

### Provider-Specific Kubernetes/Helm Providers

Kubernetes and Helm providers are configured based on the cluster type:

**AWS (EKS):**
- Uses AWS EKS cluster data and auth token

**Azure (AKS):**
- Uses AKS kube_config with client certificates

**GCP (GKE):**
- Uses GKE endpoint with Google Cloud access token

### Multi-Provider Spoke Generation

Spoke modules are generated with provider-specific paths and identity types:

**AWS Spokes:**
```hcl
source = "../../combinations/aws/spoke"
hub_pod_identity_arns = ...
```

**Azure Spokes:**
```hcl
source = "../../combinations/azure/spoke"
hub_managed_identity_arns = ...
```

**GCP Spokes:**
```hcl
source = "../../combinations/gcp/spoke"
hub_workload_identity_arns = ...
```

Each spoke module automatically references the correct identity module based on its provider:
- AWS: `module.pod_identities`
- Azure: `module.managed_identities`
- GCP: `module.workload_identities`

### Mixed Provider Deployments

The architecture supports mixed provider deployments where:
- Hub can be on AWS, Azure, or GCP
- Each spoke independently specifies its provider
- Cross-cloud access is configured via spoke roles

Example config.yaml:
```yaml
hub:
  provider: aws
  # ... AWS hub config

spokes:
  - alias: spoke1
    enabled: true
    provider: aws
    # ... AWS spoke config

  - alias: spoke2
    enabled: true
    provider: azure
    # ... Azure spoke config

  - alias: spoke3
    enabled: true
    provider: gcp
    # ... GCP spoke config
```

