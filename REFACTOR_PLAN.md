# Gen3-KRO Repository Refactoring Plan
## Hub-Spoke Architecture with Terragrunt, Terraform, ArgoCD, and KRO

**Date**: October 8, 2025  
**Branch**: `refactor-terragrunt` → `hub-spoke-refactor`  
**Status**: Planning Phase

---

## Executive Summary

This document provides a detailed, step-by-step plan to refactor the gen3-kro repository into a clean hub-spoke architecture where:

- **Hub cluster**: Managed by Terragrunt/Terraform, hosts ArgoCD and KRO controller (as an addon)
- **Spoke clusters**: Infrastructure deployed via KRO ResourceGraphDefinitions (RGDs)
- **Spoke applications**: Deployed to spoke clusters, also managed via ArgoCD and KRO

The refactoring will establish a clear separation of concerns, improve maintainability, and create a scalable foundation for multi-account/multi-cluster deployments.

---

## Current State Analysis

### Repository Structure
```
gen3-kro/
├── terraform/
│   ├── config.yaml              # Single source of truth
│   ├── root.hcl                 # Root terragrunt config
│   ├── live/
│   │   ├── staging/             # Staging environment
│   │   └── prod/                # Production environment
│   └── modules/
│       ├── root/                # Main hub cluster module
│       ├── eks-hub/             # EKS cluster module
│       ├── argocd-bootstrap/    # ArgoCD installation
│       └── iam-access/          # IAM cross-account roles
├── argocd/
│   ├── addons/                  # Hub addons (controllers, operators)
│   ├── fleet/                   # ApplicationSets for fleet management
│   ├── platform/                # Platform-level configs
│   ├── apps/                    # Application definitions
│   └── charts/                  # Helm charts
│       ├── application-sets/
│       ├── kro/                 # KRO resource graphs
│       ├── kro-clusters/        # Spoke cluster definitions
│       └── multi-acct/
├── bootstrap/
│   ├── terragrunt-wrapper.sh   # CLI wrapper
│   └── scripts/                # Helper scripts
└── kro/                        # KRO demos and examples
```

### Current Responsibilities

#### Terraform/Terragrunt
- Provisions hub EKS cluster
- Configures IAM roles for cross-account access
- Installs ArgoCD via Terraform module
- Manages AWS infrastructure (VPC, EKS, IAM)

#### ArgoCD
- **addons/**: Deploys controllers (ACK, KRO controller, etc.) to hub
- **fleet/**: ApplicationSets for managing spoke clusters
- **platform/**: Platform-level services
- **apps/**: Application deployments (frontend/backend)
- **charts/kro/**: Contains RGD definitions for spokes
- **charts/kro-clusters/**: Helm chart for spoke cluster instances

#### KRO
- Controller runs on hub as an addon
- RGDs define spoke cluster infrastructure (EKS, VPC, IAM, etc.)
- RGDs also define spoke application deployments

### Key Findings

1. **Mixed concerns**: RGDs are in `argocd/charts/kro/` but should be separated by purpose
2. **Flat structure**: No clear hub vs spoke separation in repository
3. **Module paths**: Currently use `${get_repo_root()}/terraform//modules/root`
4. **ArgoCD layering**: Uses sophisticated value file layering (default → tenant → env)
5. **Single config**: `terraform/config.yaml` drives all infrastructure decisions
6. **ApplicationSets**: Heavily used for fleet management with cluster selectors

---

## Target Architecture

### New Directory Structure
```
gen3-kro/
├── hub/
│   ├── terraform/
│   │   ├── live/
│   │   │   ├── terragrunt.hcl           # Root config (shared)
│   │   │   ├── staging/
│   │   │   │   └── us-east-1/
│   │   │   │       ├── _env/
│   │   │   │       │   └── terragrunt.hcl   # Env-wide settings
│   │   │   │       ├── networking/
│   │   │   │       │   └── terragrunt.hcl   # VPC stack
│   │   │   │       ├── platform/
│   │   │   │       │   └── terragrunt.hcl   # EKS + ArgoCD stack
│   │   │   │       └── security/
│   │   │   │           └── terragrunt.hcl   # IAM stack
│   │   │   └── prod/
│   │   │       └── us-east-1/
│   │   │           └── ...
│   │   ├── modules/
│   │   │   ├── networking/
│   │   │   │   └── vpc/                 # VPC module
│   │   │   ├── platform/
│   │   │   │   ├── eks-hub/             # EKS cluster module
│   │   │   │   └── argocd-bootstrap/    # ArgoCD installation
│   │   │   └── security/
│   │   │       └── iam-access/          # Cross-account IAM
│   │   └── providers.hcl                # Shared provider config
│   └── argocd/
│       ├── bootstrap/
│       │   ├── base/
│       │   │   ├── kustomization.yaml
│       │   │   ├── namespace.yaml
│       │   │   ├── argocd-install.yaml
│       │   │   └── app-of-apps.yaml     # Root Application
│       │   └── overlays/
│       │       ├── staging/
│       │       │   └── kustomization.yaml
│       │       └── prod/
│       │           └── kustomization.yaml
│       ├── addons/
│       │   ├── kro-controller/          # KRO controller addon
│       │   │   ├── base/
│       │   │   │   ├── kustomization.yaml
│       │   │   │   └── application.yaml
│       │   │   └── overlays/
│       │   │       ├── staging/
│       │   │       └── prod/
│       │   ├── ack-controllers/         # ACK controllers
│       │   │   ├── iam/
│       │   │   ├── eks/
│       │   │   ├── ec2/
│       │   │   └── ...
│       │   ├── external-secrets/
│       │   ├── metrics-server/
│       │   ├── kyverno/
│       │   └── ...
│       └── charts/
│           └── application-sets/        # Reusable AppSet chart
│
├── spokes/
│   ├── spoke-template/                  # Template for new spokes
│   │   ├── infrastructure/
│   │   │   ├── base/
│   │   │   │   ├── kustomization.yaml
│   │   │   │   └── eks-cluster-rgd.yaml     # KRO RGD for EKS
│   │   │   └── overlays/
│   │   │       ├── dev/
│   │   │       ├── staging/
│   │   │       └── prod/
│   │   ├── applications/
│   │   │   ├── app-a/
│   │   │   │   ├── base/
│   │   │   │   └── overlays/
│   │   │   └── app-b/
│   │   └── argocd/
│   │       ├── base/
│   │       │   ├── kustomization.yaml
│   │       │   ├── infrastructure-app.yaml  # App for infra RGD
│   │       │   └── applications-appset.yaml # AppSet for apps
│   │       └── overlays/
│   │           ├── dev/
│   │           ├── staging/
│   │           └── prod/
│   ├── spoke1/                          # Actual spoke instance
│   │   └── ... (same structure)
│   └── spoke2/
│       └── ...
│
├── shared/
│   ├── kro-rgds/                        # Reusable RGD library
│   │   ├── aws/
│   │   │   ├── eks-cluster.yaml
│   │   │   ├── vpc-network.yaml
│   │   │   ├── rds-database.yaml
│   │   │   └── iam-roles.yaml
│   │   └── kubernetes/
│   │       ├── namespace.yaml
│   │       └── pod-identity.yaml
│   └── helm-charts/                     # Shared Helm charts
│       └── ...
│
├── config/
│   ├── config.yaml                      # Main config (moved from terraform/)
│   ├── environments/
│   │   ├── staging.yaml
│   │   └── prod.yaml
│   └── spokes/
│       ├── spoke1.yaml
│       └── spoke2.yaml
│
├── bootstrap/
│   ├── terragrunt-wrapper.sh
│   └── scripts/
│
└── docs/
    ├── hub-deployment.md
    ├── spoke-deployment.md
    └── kro-patterns.md
```

### Architectural Principles

1. **Hub manages infrastructure for spokes via KRO**
   - KRO controller runs as hub addon
   - RGDs for spoke infrastructure live in `spokes/<spoke>/infrastructure/`
   - RGD instances are managed by ArgoCD ApplicationSets

2. **Clear separation of concerns**
   - `hub/terraform/`: Hub cluster infrastructure only
   - `hub/argocd/addons/`: Hub-level controllers and operators
   - `spokes/<spoke>/infrastructure/`: Spoke cluster RGDs
   - `spokes/<spoke>/applications/`: Spoke workloads
   - `shared/`: Reusable RGDs and charts

3. **Environment-specific overlays**
   - Kustomize overlays for dev/staging/prod
   - Helm value files for environment-specific config
   - Terragrunt env directories with `_env/terragrunt.hcl`

4. **GitOps-driven deployments**
   - Hub ArgoCD manages all spoke deployments
   - ApplicationSets for fleet management
   - Sync waves for ordered deployment

---

## Migration Strategy

### Phase 1: Preparation and Validation Setup
**Duration**: 1-2 days  
**Risk**: Low

#### 1.1 Create New Branch
```bash
cd /workspaces/gen3-kro
git checkout refactor-terragrunt
git pull origin refactor-terragrunt
git checkout -b hub-spoke-refactor
```

#### 1.2 Backup Current State
```bash
# Create backup of outputs
mkdir -p outputs/backups/pre-refactor-$(date +%Y%m%d)
cp -r outputs/* outputs/backups/pre-refactor-$(date +%Y%m%d)/

# Document current terraform state
./bootstrap/terragrunt-wrapper.sh staging validate > outputs/pre-refactor-validation.log
```

#### 1.3 Create Validation Scripts

Create `bootstrap/scripts/validate-structure.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Validate new structure
echo "=== Validating Repository Structure ==="

# Check hub terraform
echo "Validating hub terraform modules..."
for module in hub/terraform/modules/*; do
  if [[ -f "$module/main.tf" ]]; then
    echo "✓ Found $module"
  fi
done

# Check spoke structure
echo "Validating spoke structure..."
for spoke in spokes/*/; do
  if [[ -f "$spoke/infrastructure/base/kustomization.yaml" ]]; then
    echo "✓ Spoke $(basename $spoke) has valid infrastructure"
  fi
done

# Validate kustomize builds
echo "Validating kustomize builds..."
kustomize build hub/argocd/bootstrap/base
kustomize build hub/argocd/addons/kro-controller/base

# Validate helm charts
echo "Validating helm charts..."
for chart in hub/argocd/charts/*/; do
  if [[ -f "$chart/Chart.yaml" ]]; then
    helm template test "$chart" --dry-run
  fi
done

echo "=== Validation Complete ==="
```

Create `bootstrap/scripts/validate-terragrunt.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-staging}
REGION=${2:-us-east-1}

echo "=== Validating Terragrunt Configuration ==="
echo "Environment: $ENV"
echo "Region: $REGION"

cd "hub/terraform/live/$ENV/$REGION"

# Format check
echo "Running terragrunt hclfmt..."
terragrunt hclfmt --terragrunt-check

# Initialize all stacks
echo "Initializing stacks..."
terragrunt run-all init --terragrunt-non-interactive

# Validate all stacks
echo "Validating stacks..."
terragrunt run-all validate

echo "=== Terragrunt Validation Complete ==="
```

### Phase 2: Scaffold New Structure
**Duration**: 1 day  
**Risk**: Low (no changes to existing code)

#### 2.1 Create Hub Directory Structure
```bash
mkdir -p hub/terraform/{live,modules,}
mkdir -p hub/terraform/modules/{networking,platform,security}
mkdir -p hub/terraform/live/{staging,prod}/us-east-1/{_env,networking,platform,security}
mkdir -p hub/argocd/{bootstrap,addons,charts}
mkdir -p hub/argocd/bootstrap/{base,overlays/{staging,prod}}
mkdir -p hub/argocd/charts/application-sets
```

#### 2.2 Create Spokes Directory Structure
```bash
mkdir -p spokes/spoke-template/{infrastructure,applications,argocd}
mkdir -p spokes/spoke-template/infrastructure/{base,overlays/{dev,staging,prod}}
mkdir -p spokes/spoke-template/argocd/{base,overlays/{dev,staging,prod}}
```

#### 2.3 Create Shared Resources
```bash
mkdir -p shared/kro-rgds/{aws,kubernetes}
mkdir -p shared/helm-charts
mkdir -p config/{environments,spokes}
```

#### 2.4 Create Placeholder Files
```bash
# Hub kustomization base
cat > hub/argocd/bootstrap/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd

resources:
  - namespace.yaml
  - app-of-apps.yaml
EOF

# Spoke template kustomization
cat > spokes/spoke-template/infrastructure/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - eks-cluster-rgd.yaml
EOF
```

### Phase 3: Migrate Terraform Modules
**Duration**: 2-3 days  
**Risk**: Medium

#### 3.1 Move and Reorganize Modules

```bash
# Move modules to new locations with clear domains
git mv terraform/modules/eks-hub hub/terraform/modules/platform/
git mv terraform/modules/argocd-bootstrap hub/terraform/modules/platform/
git mv terraform/modules/iam-access hub/terraform/modules/security/

# Create new VPC module (extract from root if needed)
mkdir -p hub/terraform/modules/networking/vpc
# ... extract VPC resources from root module
```

#### 3.2 Create Shared Provider Configuration

Create `hub/terraform/providers.hcl`:
```hcl
# Shared provider configuration
# Generated into each stack via terragrunt generate block

generate "provider_aws" {
  path      = "providers_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region  = var.aws_region
      profile = var.aws_profile
      
      default_tags {
        tags = var.common_tags
      }
    }
  EOF
}

generate "provider_kubernetes" {
  path      = "providers_kubernetes.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = var.cluster_endpoint
      cluster_ca_certificate = base64decode(var.cluster_ca_data)
      
      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args = [
          "eks",
          "get-token",
          "--cluster-name",
          var.cluster_name,
          "--region",
          var.aws_region,
          "--profile",
          var.aws_profile
        ]
      }
    }
    
    provider "helm" {
      kubernetes {
        host                   = var.cluster_endpoint
        cluster_ca_certificate = base64decode(var.cluster_ca_data)
        
        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args = [
            "eks",
            "get-token",
            "--cluster-name",
            var.cluster_name,
            "--region",
            var.aws_region,
            "--profile",
            var.aws_profile
          ]
        }
      }
    }
  EOF
}
```

#### 3.3 Create Root Terragrunt Configuration

Move `terraform/root.hcl` to `hub/terraform/live/terragrunt.hcl` and update:

```hcl
# hub/terraform/live/terragrunt.hcl
# Root-level Terragrunt configuration

locals {
  # Load centralized configuration from YAML
  config_file = "${get_repo_root()}/config/config.yaml"
  config      = yamldecode(file(local.config_file))

  # Extract configuration sections
  hub        = local.config.hub
  ack        = local.config.ack
  spokes     = local.config.spokes
  gitops     = local.config.gitops
  paths      = local.config.paths
  deployment = local.config.deployment
  addons     = local.config.addons

  # Common tags applied to all resources
  common_tags = {
    ManagedBy  = "Terragrunt"
    Repository = "gen3-kro"
    Blueprint  = "hub-spoke-eks-gitops"
    Owner      = "platform-engineering"
  }
}

# Remote state configuration
remote_state {
  backend = "s3"
  
  config = {
    bucket  = local.paths.terraform_state_bucket
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = local.hub.aws_region
    encrypt = true
    
    s3_bucket_tags = merge(
      local.common_tags,
      {
        Name        = "gen3-kro-terraform-state"
        Purpose     = "Terraform state storage"
        Environment = "shared"
      }
    )
  }
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = file("${get_repo_root()}/hub/terraform/providers.hcl")
}
```

#### 3.4 Create Environment-Level Configuration

Create `hub/terraform/live/staging/us-east-1/_env/terragrunt.hcl`:

```hcl
# Environment-wide settings for staging/us-east-1

locals {
  # Load root configuration
  root_config = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
  config      = local.root_config.locals.config
  
  # Environment-specific settings
  environment = "staging"
  region      = "us-east-1"
  
  # Naming
  cluster_name = "${local.config.hub.cluster_name}-${local.environment}"
  vpc_name     = "${local.config.hub.vpc_name}-${local.environment}"
  
  # Tags
  env_tags = {
    Environment = local.environment
    Region      = local.region
  }
  
  common_tags = merge(
    local.root_config.locals.common_tags,
    local.env_tags
  )
}

# Make environment variables available to all stacks
inputs = {
  environment  = local.environment
  region       = local.region
  cluster_name = local.cluster_name
  vpc_name     = local.vpc_name
  common_tags  = local.common_tags
}
```

#### 3.5 Create Stack-Level Configurations

Create `hub/terraform/live/staging/us-east-1/networking/terragrunt.hcl`:

```hcl
# VPC and networking stack

include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env/terragrunt.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/hub/terraform/modules/networking/vpc"
}

inputs = {
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets      = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = true
}
```

Create `hub/terraform/live/staging/us-east-1/platform/terragrunt.hcl`:

```hcl
# EKS cluster and ArgoCD stack

include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env/terragrunt.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/hub/terraform/modules/platform/eks-hub"
}

dependency "networking" {
  config_path = "../networking"
  
  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-mock1", "subnet-mock2"]
    public_subnets  = ["subnet-mock3", "subnet-mock4"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  vpc_id             = dependency.networking.outputs.vpc_id
  private_subnet_ids = dependency.networking.outputs.private_subnets
  public_subnet_ids  = dependency.networking.outputs.public_subnets
  
  kubernetes_version = "1.33"
  node_groups = {
    general = {
      desired_size = 2
      min_size     = 1
      max_size     = 4
      instance_types = ["t3.large"]
    }
  }
}
```

Create `hub/terraform/live/staging/us-east-1/security/terragrunt.hcl`:

```hcl
# IAM roles for cross-account access

include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "env" {
  path   = find_in_parent_folders("_env/terragrunt.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/hub/terraform/modules/security/iam-access"
}

dependency "platform" {
  config_path = "../platform"
  
  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  oidc_provider_arn = dependency.platform.outputs.oidc_provider_arn
  spoke_accounts    = local.root_config.locals.config.spokes
}
```

### Phase 4: Migrate ArgoCD Manifests
**Duration**: 3-4 days  
**Risk**: High (impacts GitOps)

#### 4.1 Create Hub Bootstrap Manifests

Create `hub/argocd/bootstrap/base/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
```

Create `hub/argocd/bootstrap/base/app-of-apps.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hub-root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/indiana-university/gen3-kro
    targetRevision: main
    path: hub/argocd/addons
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Create `hub/argocd/bootstrap/base/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - app-of-apps.yaml
```

#### 4.2 Migrate KRO Controller Addon

Create `hub/argocd/addons/kro-controller/base/application.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kro-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/awslabs/kro
    targetRevision: v0.1.0
    path: charts/kro-controller
    helm:
      releaseName: kro-controller
      values: |
        replicas: 2
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: kro-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

#### 4.3 Migrate ACK Controllers

For each ACK controller (IAM, EKS, EC2, etc.), create structure:

```
hub/argocd/addons/ack-controllers/
├── base/
│   ├── kustomization.yaml
│   └── applicationset.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── values-staging.yaml
    └── prod/
        ├── kustomization.yaml
        └── values-prod.yaml
```

Create `hub/argocd/addons/ack-controllers/base/applicationset.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ack-controllers
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  goTemplate: true
  generators:
    - list:
        elements:
          - name: iam
            version: "1.3.16"
            namespace: ack-system
            serviceAccount: ack-iam-controller
          - name: eks
            version: "1.6.0"
            namespace: ack-system
            serviceAccount: ack-eks-controller
          - name: ec2
            version: "1.3.4"
            namespace: ack-system
            serviceAccount: ack-ec2-controller
  template:
    metadata:
      name: ack-{{.name}}-controller
    spec:
      project: default
      source:
        repoURL: public.ecr.aws
        chart: aws-controllers-k8s/{{.name}}-chart
        targetRevision: "{{.version}}"
        helm:
          releaseName: ack-{{.name}}
          values: |
            aws:
              region: us-east-1
            serviceAccount:
              name: {{.serviceAccount}}
      destination:
        server: https://kubernetes.default.svc
        namespace: {{.namespace}}
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

#### 4.4 Create Addons Index

Create `hub/argocd/addons/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - kro-controller/base
  - ack-controllers/base
  - external-secrets/base
  - metrics-server/base
  - kyverno/base
```

### Phase 5: Migrate Spoke Definitions
**Duration**: 2-3 days  
**Risk**: Medium

#### 5.1 Extract Spoke RGDs

Move existing RGDs from `argocd/charts/kro/resource-groups/` to shared library:

```bash
# Move EKS RGDs to shared
git mv argocd/charts/kro/resource-groups/eks/rg-eks.yaml \
        shared/kro-rgds/aws/eks-cluster.yaml

git mv argocd/charts/kro/resource-groups/eks/rg-vpc.yaml \
        shared/kro-rgds/aws/vpc-network.yaml

git mv argocd/charts/kro/resource-groups/iam/rg-iam.yaml \
        shared/kro-rgds/aws/iam-roles.yaml
```

#### 5.2 Create Spoke Template

Create `spokes/spoke-template/infrastructure/base/eks-cluster-rgd.yaml`:
```yaml
# Reference the shared RGD and create instance
apiVersion: kro.run/v1alpha1
kind: EksCluster
metadata:
  name: spoke-template-cluster
  namespace: default
spec:
  name: spoke-template
  tenant: auto1
  environment: staging
  region: us-west-2
  k8sVersion: "1.32"
  accountId: "123456789012"
  managementAccountId: "987654321098"
  vpc:
    create: true
    vpcCidr: "10.1.0.0/16"
    publicSubnet1Cidr: "10.1.1.0/24"
    publicSubnet2Cidr: "10.1.2.0/24"
    privateSubnet1Cidr: "10.1.11.0/24"
    privateSubnet2Cidr: "10.1.12.0/24"
  addons:
    enable_metrics_server: "true"
    enable_external_secrets: "true"
    enable_kyverno: "true"
```

Create `spokes/spoke-template/argocd/base/infrastructure-app.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: spoke-template-infrastructure
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/indiana-university/gen3-kro
    targetRevision: main
    path: spokes/spoke-template/infrastructure/base
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: false  # Don't auto-delete infrastructure
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Create `spokes/spoke-template/argocd/base/applications-appset.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: spoke-template-apps
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  goTemplate: true
  generators:
    - git:
        repoURL: https://github.com/indiana-university/gen3-kro
        revision: main
        directories:
          - path: spokes/spoke-template/applications/*
  template:
    metadata:
      name: spoke-template-{{.path.basename}}
    spec:
      project: default
      source:
        repoURL: https://github.com/indiana-university/gen3-kro
        targetRevision: main
        path: '{{.path.path}}/base'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

#### 5.3 Create Fleet Management AppSet

Create `hub/argocd/fleet/spoke-fleet.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: spoke-fleet
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  goTemplate: true
  generators:
    - git:
        repoURL: https://github.com/indiana-university/gen3-kro
        revision: main
        directories:
          - path: spokes/*
            exclude: spoke-template
  template:
    metadata:
      name: '{{.path.basename}}-fleet'
    spec:
      project: default
      source:
        repoURL: https://github.com/indiana-university/gen3-kro
        targetRevision: main
        path: '{{.path.path}}/argocd/base'
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### Phase 6: Update Configuration Files
**Duration**: 1 day  
**Risk**: Low

#### 6.1 Move and Split Config

```bash
# Move main config
git mv terraform/config.yaml config/config.yaml

# Create environment-specific configs
cat > config/environments/staging.yaml <<'EOF'
# Staging environment overrides
environment: staging
enable_cross_account_iam: false  # Same account
cluster_name_suffix: staging

addons:
  enable_metrics_server: true
  enable_kyverno: true
  enable_cert_manager: false
  enable_external_dns: false
EOF

cat > config/environments/prod.yaml <<'EOF'
# Production environment overrides
environment: prod
enable_cross_account_iam: true
cluster_name_suffix: prod

addons:
  enable_metrics_server: true
  enable_kyverno: true
  enable_cert_manager: true
  enable_external_dns: true
EOF
```

#### 6.2 Create Spoke Configs

```bash
cat > config/spokes/spoke1.yaml <<'EOF'
# Spoke1 configuration
alias: spoke1
region: us-east-1
account_id: "123456789012"
vpc_cidr: "10.1.0.0/16"

tags:
  Team: platform
  Purpose: demo
  CostCenter: engineering
EOF
```

### Phase 7: Update Path References
**Duration**: 2 days  
**Risk**: High

#### 7.1 Update Terragrunt Source Paths

Run global search and replace:
```bash
# Find all terragrunt.hcl files
find . -name "terragrunt.hcl" -type f

# Update module references
# OLD: source = "${get_repo_root()}/terraform//modules/root"
# NEW: source = "${get_repo_root()}/hub/terraform/modules/platform/eks-hub"

# Use sed or manual replacement
find hub/terraform/live -name "terragrunt.hcl" -exec sed -i \
  's|terraform//modules/|hub/terraform/modules/|g' {} \;
```

#### 7.2 Update ArgoCD Paths

Update all Application and ApplicationSet manifests:
```bash
# Find all ArgoCD manifests
find hub/argocd spokes/ -name "*.yaml" -type f

# Update repoURL paths
# OLD: path: argocd/addons
# NEW: path: hub/argocd/addons
```

Create script `bootstrap/scripts/update-argocd-paths.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Update ArgoCD Application paths
find hub/argocd spokes/ -name "*.yaml" -type f | while read -r file; do
  sed -i 's|path: argocd/addons|path: hub/argocd/addons|g' "$file"
  sed -i 's|path: argocd/fleet|path: hub/argocd/fleet|g' "$file"
  sed -i 's|path: argocd/platform|path: hub/argocd/platform|g' "$file"
  sed -i 's|path: argocd/apps|path: spokes/|g' "$file"
  sed -i 's|path: argocd/charts|path: hub/argocd/charts|g' "$file"
done
```

#### 7.3 Update Config References

```bash
# Update references to config.yaml
grep -r "terraform/config.yaml" . --exclude-dir=.git

# Replace with config/config.yaml
find . -name "*.hcl" -o -name "*.sh" | xargs sed -i \
  's|terraform/config\.yaml|config/config.yaml|g'
```

#### 7.4 Update Bootstrap Scripts

Update `bootstrap/terragrunt-wrapper.sh`:
```bash
# OLD: CONFIG_FILE="$REPO_ROOT/terraform/config.yaml"
# NEW: CONFIG_FILE="$REPO_ROOT/config/config.yaml"

# OLD: cd "$REPO_ROOT/terraform/live/$ENV"
# NEW: cd "$REPO_ROOT/hub/terraform/live/$ENV/us-east-1"
```

### Phase 8: Testing and Validation
**Duration**: 3-4 days  
**Risk**: Critical

#### 8.1 Validate Terragrunt Configuration

```bash
# Test staging environment
./bootstrap/scripts/validate-terragrunt.sh staging us-east-1

# Expected: All validations pass
# - hclfmt check passes
# - terragrunt init succeeds for all stacks
# - terragrunt validate succeeds for all stacks
```

#### 8.2 Validate Kustomize Builds

```bash
# Test hub bootstrap
kustomize build hub/argocd/bootstrap/base
kustomize build hub/argocd/bootstrap/overlays/staging

# Test hub addons
kustomize build hub/argocd/addons/kro-controller/base
kustomize build hub/argocd/addons/ack-controllers/base

# Test spoke template
kustomize build spokes/spoke-template/infrastructure/base
kustomize build spokes/spoke-template/argocd/base

# Expected: All builds succeed with valid YAML
```

#### 8.3 Validate Helm Charts

```bash
# Test any remaining Helm charts
for chart in hub/argocd/charts/*/; do
  if [[ -f "$chart/Chart.yaml" ]]; then
    echo "Testing $chart"
    helm template test "$chart" --dry-run
  fi
done

# Expected: All helm templates render successfully
```

#### 8.4 Test Terragrunt Plan (Dry Run)

```bash
# Generate plan for staging without applying
cd hub/terraform/live/staging/us-east-1

# Plan networking
cd networking
terragrunt plan -out=tfplan
cd ..

# Plan platform (will use mock outputs from networking)
cd platform
terragrunt plan -out=tfplan
cd ..

# Plan security
cd security
terragrunt plan -out=tfplan
cd ..

# Expected: Plans should show creation of resources, no errors
# Review plans for unexpected changes
```

#### 8.5 Validate ArgoCD Applications

```bash
# Install ArgoCD CLI if not present
# Validate application manifests
argocd app validate hub/argocd/bootstrap/base/app-of-apps.yaml

# Diff against existing cluster (if available)
argocd app diff hub-root --local hub/argocd/bootstrap/base

# Expected: Manifests are valid, diffs show intentional changes only
```

### Phase 9: Pilot Deployment
**Duration**: 2-3 days  
**Risk**: High

#### 9.1 Deploy to Test/Dev Environment

```bash
# Create a fresh dev environment for testing
# OR use existing staging with caution

# Deploy networking
cd hub/terraform/live/staging/us-east-1/networking
terragrunt apply

# Deploy platform (EKS + ArgoCD)
cd ../platform
terragrunt apply

# Wait for EKS cluster to be ready
aws eks update-kubeconfig --name gen3-kro-hub-staging --region us-east-1

# Verify cluster access
kubectl get nodes

# Deploy security (IAM roles)
cd ../security
terragrunt apply
```

#### 9.2 Bootstrap ArgoCD

```bash
# Apply hub bootstrap
kubectl apply -k hub/argocd/bootstrap/overlays/staging

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=600s \
  deployment/argocd-server -n argocd

# Get ArgoCD admin password
./bootstrap/scripts/connect-cluster.sh staging

# Login to ArgoCD UI and verify app-of-apps is synced
```

#### 9.3 Deploy Spoke (Pilot)

```bash
# Create spoke1 from template
cp -r spokes/spoke-template spokes/spoke1

# Update spoke1 configuration
# Edit spokes/spoke1/infrastructure/base/eks-cluster-rgd.yaml
# Edit config/spokes/spoke1.yaml

# Apply spoke fleet ApplicationSet
kubectl apply -f hub/argocd/fleet/spoke-fleet.yaml

# Monitor spoke1 infrastructure creation
kubectl get ekscluster -w

# Check KRO controller logs
kubectl logs -n kro-system -l app=kro-controller -f

# Verify spoke resources are created in AWS
aws eks list-clusters --region us-east-1
```

#### 9.4 Validate End-to-End

```bash
# Verify spoke cluster is created
aws eks describe-cluster --name spoke1 --region us-east-1

# Get spoke cluster kubeconfig
aws eks update-kubeconfig --name spoke1 --region us-east-1

# Verify spoke cluster is healthy
kubectl --context spoke1 get nodes

# Deploy test application to spoke
# Edit spokes/spoke1/applications/test-app/base/...
# Commit and push
# Watch ArgoCD sync the app

# Verify app is running on spoke
kubectl --context spoke1 get pods -n test-app
```

### Phase 10: Documentation and Cleanup
**Duration**: 1-2 days  
**Risk**: Low

#### 10.1 Update Documentation

Create/update these files:
- `docs/hub-deployment.md` - How to deploy hub cluster
- `docs/spoke-deployment.md` - How to create and deploy spokes
- `docs/kro-patterns.md` - Common KRO RGD patterns
- `docs/migration-notes.md` - What changed and why
- `README.md` - Update with new structure

#### 10.2 Create Runbooks

Create `docs/runbooks/`:
- `deploy-hub-cluster.md`
- `create-spoke-cluster.md`
- `troubleshooting-kro.md`
- `disaster-recovery.md`

#### 10.3 Clean Up Old Structure

```bash
# Archive old structure
mkdir -p archive/pre-refactor
git mv terraform/live archive/pre-refactor/
git mv argocd/addons/bootstrap archive/pre-refactor/
git mv argocd/fleet archive/pre-refactor/

# Remove obsolete files
git rm argocd/charts/kro-clusters  # Now in spokes/
git rm terraform/modules  # Moved to hub/terraform/modules

# Commit cleanup
git add -A
git commit -m "refactor: clean up old structure after migration"
```

#### 10.4 Update CI/CD

Update GitHub Actions workflows:
- Update paths to watch for changes
- Update terraform/terragrunt commands to use new paths
- Update kustomize build commands

Example `.github/workflows/terraform.yml`:
```yaml
name: Terraform CI

on:
  pull_request:
    paths:
      - 'hub/terraform/**'
      - 'config/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Terragrunt Format
        run: |
          cd hub/terraform/live
          terragrunt hclfmt --check --terragrunt-check
      - name: Terragrunt Validate
        run: |
          cd hub/terraform/live/staging/us-east-1
          terragrunt run-all validate
```

---

## Validation Checklist

### Pre-Migration
- [ ] All current infrastructure is in a clean state
- [ ] Backup of current outputs created
- [ ] Current validation logs captured
- [ ] Team notified of migration plan

### Structure
- [ ] Hub directory structure created
- [ ] Spokes directory structure created
- [ ] Shared resources directory created
- [ ] Config directory created
- [ ] Placeholder files in place

### Terraform/Terragrunt
- [ ] Modules moved to hub/terraform/modules/
- [ ] Module paths organized by domain (networking, platform, security)
- [ ] Root terragrunt.hcl moved to hub/terraform/live/
- [ ] Environment configs created with _env/ pattern
- [ ] Stack configs created (networking, platform, security)
- [ ] Provider configuration extracted to shared file
- [ ] All source paths updated to new locations
- [ ] Terragrunt hclfmt passes
- [ ] Terragrunt init succeeds for all stacks
- [ ] Terragrunt validate succeeds for all stacks
- [ ] Terragrunt plan runs without errors

### ArgoCD
- [ ] Hub bootstrap manifests created
- [ ] Hub addons migrated (KRO controller, ACK, etc.)
- [ ] Spoke template created
- [ ] Fleet management ApplicationSet created
- [ ] All Application paths updated
- [ ] All ApplicationSet paths updated
- [ ] Kustomize builds succeed for all bases
- [ ] Kustomize builds succeed for all overlays
- [ ] Helm charts validate successfully

### KRO
- [ ] RGDs moved to shared/kro-rgds/
- [ ] Spoke infrastructure RGDs created
- [ ] RGD instances reference correct definitions
- [ ] Sync waves configured correctly

### Configuration
- [ ] Main config moved to config/config.yaml
- [ ] Environment configs created
- [ ] Spoke configs created
- [ ] All config references updated in code
- [ ] Config validation passes

### Scripts
- [ ] terragrunt-wrapper.sh updated for new paths
- [ ] connect-cluster.sh updated for new paths
- [ ] Validation scripts created and tested
- [ ] Path update scripts created and run

### Testing
- [ ] Validation suite passes completely
- [ ] Pilot deployment succeeds
- [ ] Spoke creation via KRO works
- [ ] Application deployment to spoke works
- [ ] End-to-end workflow validated

### Documentation
- [ ] Hub deployment guide created
- [ ] Spoke deployment guide created
- [ ] KRO patterns documented
- [ ] Migration notes documented
- [ ] README updated
- [ ] Runbooks created

### Cleanup
- [ ] Old structure archived
- [ ] Obsolete files removed
- [ ] CI/CD workflows updated
- [ ] Final commit with clean structure

---

## Risk Mitigation

### High-Risk Activities
1. **Changing Terraform state paths**
   - Mitigation: Use `terraform state mv` if needed
   - Keep state bucket unchanged
   - Test with fresh environment first

2. **Breaking ArgoCD sync**
   - Mitigation: Test in dev environment first
   - Keep old paths temporarily with redirects
   - Have rollback plan ready

3. **KRO RGD changes**
   - Mitigation: Test RGDs in isolation
   - Use sync waves to control order
   - Monitor KRO controller logs closely

### Rollback Plan

If issues occur during migration:

1. **Terraform/Terragrunt issues**
   ```bash
   # Revert to previous branch
   git checkout refactor-terragrunt
   
   # Restore state if needed
   aws s3 cp s3://gen3-kro-envs-4852/backup/ . --recursive
   ```

2. **ArgoCD sync issues**
   ```bash
   # Pause all applications
   argocd app set <app-name> --sync-policy none
   
   # Revert manifests
   git revert <commit-hash>
   git push
   ```

3. **KRO issues**
   ```bash
   # Delete problematic instances
   kubectl delete ekscluster <spoke-name>
   
   # Check controller logs
   kubectl logs -n kro-system -l app=kro-controller
   ```

---

## Timeline Estimate

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| 1. Preparation | 1-2 days | None |
| 2. Scaffold | 1 day | Phase 1 |
| 3. Migrate Terraform | 2-3 days | Phase 2 |
| 4. Migrate ArgoCD | 3-4 days | Phase 2 |
| 5. Migrate Spokes | 2-3 days | Phase 4 |
| 6. Update Config | 1 day | Phase 3, 4, 5 |
| 7. Update Paths | 2 days | Phase 3, 4, 5 |
| 8. Testing | 3-4 days | Phase 7 |
| 9. Pilot Deploy | 2-3 days | Phase 8 |
| 10. Documentation | 1-2 days | Phase 9 |

**Total Estimated Time**: 18-27 days (3.5-5.5 weeks)

**Recommended Approach**: Allocate 6 weeks with buffer for unexpected issues.

---

## Success Criteria

Migration is considered successful when:

1. ✅ All Terragrunt stacks deploy successfully to staging
2. ✅ Hub cluster runs ArgoCD and KRO controller
3. ✅ At least one spoke cluster is deployed via KRO RGD
4. ✅ At least one application deploys to the spoke
5. ✅ All validation scripts pass
6. ✅ Documentation is complete and accurate
7. ✅ Team can create new spokes from template
8. ✅ CI/CD pipelines work with new structure
9. ✅ No regressions in existing functionality
10. ✅ Rollback plan tested and verified

---

## Next Steps

1. **Review this plan** with the team
2. **Approve pilot scope** (environment, spokes, apps)
3. **Create migration branch** from refactor-terragrunt
4. **Begin Phase 1** (Preparation)
5. **Schedule checkpoints** after each phase
6. **Assign ownership** for different components

---

## Questions to Resolve

1. Should we keep `terraform/` as a legacy fallback during migration?
2. What is the approval process for pilot deployment?
3. Do we need a separate dev environment or use staging?
4. How do we handle existing stateful resources during migration?
5. What is the rollback window if issues are discovered?
6. Should we migrate all spokes at once or incrementally?

---

**Document Version**: 1.0  
**Last Updated**: October 8, 2025  
**Owner**: Platform Engineering Team
