# Terragrunt Infrastructure

> Infrastructure-as-Code for gen3-kro using Terragrunt wrapper around Terraform

## Overview

This directory contains all Terragrunt configurations and Terraform modules for provisioning the gen3-kro infrastructure. The setup uses a **single YAML configuration file** (`config.yaml`) as the source of truth, with Terragrunt dynamically generating provider and backend configurations.

## Architecture

### Terragrunt vs Terraform

**CRITICAL**: This project uses **Terragrunt**, not vanilla Terraform.

- **Terragrunt** is a wrapper that generates Terraform configuration files
- Users **NEVER** run `terraform` commands directly - always use `terragrunt` or the wrapper script
- `.terragrunt-cache/` contains **auto-generated** Terraform files - never edit manually

See: [docs/terragrunt/vs-terraform.md](../docs/terragrunt/vs-terraform.md) for comprehensive explanation.

### Directory Structure

```
terraform/
├── config.yaml              # ✅ Single source of truth (YAML config)
├── root.hcl                 # ✅ Root Terragrunt configuration
├── .terraform-version       # ✅ Version pinning (1.5.7)
│
├── live/                    # ✅ Environment-specific Terragrunt configs
│   ├── prod/
│   │   ├── terragrunt.hcl  # Production environment config
│   │   └── .terragrunt-cache/  # Generated Terraform files (gitignored)
│   └── staging/
│       ├── terragrunt.hcl  # Staging environment config
│       └── .terragrunt-cache/  # Generated Terraform files (gitignored)
│
└── modules/                 # ✅ Terraform modules (source code)
    ├── root/                # Orchestrator module
    │   ├── main.tf         # Always creates EKS (no Kind)
    │   ├── locals.tf
    │   └── variables.tf
    ├── eks-hub/            # Production EKS + VPC
    ├── iam-access/         # Cross-account IAM
    └── argocd-bootstrap/   # ArgoCD installation
```

## Configuration

### Single Configuration File: `config.yaml`

All infrastructure is configured via **one YAML file**:

```yaml
# Hub cluster configuration
hub:
  aws_profile: "boadeyem_tf"       # AWS CLI profile for hub
  aws_region: "us-east-1"
  cluster_name: "gen3-kro-hub"
  kubernetes_version: "1.31"

# ACK controllers to deploy
ack:
  namespace: "ack-system"
  controllers:
    - rds
    - eks
    - s3
    - ec2
    - iam

# Spoke accounts (array)
spokes:
  - alias: "spoke1"
    region: "us-east-1"
    profile: "boadeyem_tf"         # AWS CLI profile
    account_id: ""                 # Auto-detected if empty
    tags:
      Environment: "prod"
      Team: "platform"

# GitOps paths
gitops:
  org_name: "indiana-university"
  repo_name: "gen3-kro"
  addons:
    path: "argocd/addons/bootstrap"
    revision: "main"
  fleet:
    path: "argocd/fleet/bootstrap"
  platform:
    path: "argocd/platform/bootstrap"
  workload:
    path: "argocd/apps/"

# KRO operator
kro:
  namespace: "kro"
  chart_version: "v0.2.0"

# Paths
paths:
  output_dir: "outputs"
  state_bucket: "gen3-kro-envs-4852"

# Deployment settings
deployment:
  enable_cross_account_iam: true
  destroy: false
```

### Environment-Specific Configurations

Each environment has its own `terragrunt.hcl` file:

**`live/staging/terragrunt.hcl`**:
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  deployment_stage = "staging"
  # Other environment-specific overrides
}
```

**`live/prod/terragrunt.hcl`**:
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  deployment_stage = "prod"
  # Other environment-specific overrides
}
```

## Usage

### CLI: Terragrunt Wrapper

**Main Script**: `../bootstrap/terragrunt-wrapper.sh`

#### Basic Commands

```bash
# Validate configuration
./bootstrap/terragrunt-wrapper.sh <environment> validate

# Plan changes
./bootstrap/terragrunt-wrapper.sh <environment> plan

# Apply infrastructure
./bootstrap/terragrunt-wrapper.sh <environment> apply

# Show outputs
./bootstrap/terragrunt-wrapper.sh <environment> output

# Destroy infrastructure (requires YES confirmation)
./bootstrap/terragrunt-wrapper.sh <environment> destroy

# Generate dependency graph
./bootstrap/terragrunt-wrapper.sh <environment> graph
```

#### Examples

```bash
# Validate staging configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# Plan staging changes
./bootstrap/terragrunt-wrapper.sh staging plan

# Apply to staging (auto-confirms)
./bootstrap/terragrunt-wrapper.sh staging apply

# Apply to production (requires typing YES)
./bootstrap/terragrunt-wrapper.sh prod apply

# Apply with auto-confirm (use with caution!)
./bootstrap/terragrunt-wrapper.sh staging apply --yes

# Enable verbose logging
./bootstrap/terragrunt-wrapper.sh staging plan --verbose

# Enable debug mode
./bootstrap/terragrunt-wrapper.sh staging plan --debug
```

### Direct Terragrunt Usage

If you prefer to use Terragrunt directly:

```bash
# Navigate to environment
cd terraform/live/staging

# Initialize
terragrunt init

# Validate
terragrunt validate

# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy
terragrunt destroy
```

### Workflow

Terragrunt processes your commands in this order:

1. Reads `config.yaml` (YAML configuration)
2. Reads `root.hcl` (root Terragrunt config)
3. Reads environment-specific `terragrunt.hcl` (e.g., `live/staging/terragrunt.hcl`)
4. **GENERATES** Terraform files in `.terragrunt-cache/`:
   - `providers.tf` - AWS provider configurations
   - `versions.tf` - Terraform and provider versions
   - `backend.tf` - S3 backend configuration
   - `kube_providers.tf` - Kubernetes/Helm providers
5. Copies Terraform modules to `.terragrunt-cache/`
6. Executes Terraform commands in the cache directory

## Modules

### root
Orchestrator module that coordinates all other modules.

**Purpose**: Main entry point, creates EKS cluster and bootstraps ArgoCD.

**Key Resources**:
- Calls `eks-hub` module for EKS cluster
- Calls `iam-access` module for cross-account IAM
- Calls `argocd-bootstrap` module for GitOps setup

### eks-hub
Production EKS cluster with VPC and all necessary components.

**Purpose**: Create and configure EKS cluster.

**Key Resources**:
- VPC with public/private subnets
- EKS cluster with managed node groups
- IRSA (IAM Roles for Service Accounts)
- Security groups
- CloudWatch log groups

### iam-access
Cross-account IAM roles for spoke account access.

**Purpose**: Enable hub cluster to manage resources in spoke accounts.

**Key Resources**:
- Assumable IAM roles in spoke accounts
- Trust policies for hub account
- Pod Identity associations for service accounts

**Architectures**:
- **External Spoke**: Cross-account IAM roles (when hub ≠ spoke account)
- **Internal Spoke**: Direct IAM roles (when hub = spoke account)

### argocd-bootstrap
ArgoCD installation and initial ApplicationSets.

**Purpose**: Install and configure ArgoCD for GitOps.

**Key Resources**:
- ArgoCD Helm chart
- Initial ApplicationSets
- GitHub App authentication
- Repository credentials

## Backend Configuration

**S3 Backend** (NO DynamoDB locking):

```hcl
bucket  = "gen3-kro-envs-4852"
region  = "us-east-1"
encrypt = true

# State isolation by environment:
# - prod:    s3://gen3-kro-envs-4852/prod/terraform.tfstate
# - staging: s3://gen3-kro-envs-4852/staging/terraform.tfstate
```

**Important**: DynamoDB locking **intentionally disabled**.

## Common Operations

### Add New Spoke Account

1. Edit `config.yaml`:
   ```yaml
   spokes:
     - alias: "spoke2"
       region: "us-west-2"
       profile: "spoke2-profile"
       account_id: "210987654321"
   ```

2. Plan and apply:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh prod plan
   ./bootstrap/terragrunt-wrapper.sh prod apply
   ```

### Update Kubernetes Version

1. Edit `config.yaml`:
   ```yaml
   hub:
     kubernetes_version: "1.32"
   ```

2. Plan and apply:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh staging plan
   ./bootstrap/terragrunt-wrapper.sh staging apply
   ```

### Add ACK Controller

1. Edit `config.yaml`:
   ```yaml
   ack:
     controllers:
       - rds
       - eks
       - s3
       - ec2
       - iam
       - lambda  # New controller
   ```

2. Plan and apply:
   ```bash
   ./bootstrap/terragrunt-wrapper.sh staging plan
   ./bootstrap/terragrunt-wrapper.sh staging apply
   ```

## Validation

### Pre-Deployment Checks

```bash
# 1. Validate YAML syntax
yq eval '.' terraform/config.yaml

# 2. Validate Terragrunt configuration
./bootstrap/terragrunt-wrapper.sh staging validate

# 3. Generate plan
./bootstrap/terragrunt-wrapper.sh staging plan

# 4. Review plan output
less terraform/live/staging/tfplan
```

### Post-Deployment Verification

```bash
# 1. Check EKS cluster
aws eks describe-cluster --name gen3-kro-hub-staging --profile boadeyem_tf

# 2. Update kubeconfig
aws eks update-kubeconfig --name gen3-kro-hub-staging --region us-east-1 --profile boadeyem_tf

# 3. Verify cluster access
kubectl get nodes

# 4. Check ArgoCD
kubectl get pods -n argocd

# 5. Check ACK controllers
kubectl get pods -n ack-system
```

## Troubleshooting

### Common Issues

**Issue**: "Plan file not found"
- **Cause**: Terragrunt creates plan in `.terragrunt-cache/<hash>/` but wrapper looks in `live/<env>/`
- **Solution**: See [docs/terragrunt/troubleshooting.md](../docs/terragrunt/troubleshooting.md)

**Issue**: "Providers not configured"
- **Cause**: Generated files missing or outdated
- **Solution**: Clean cache and reinitialize
  ```bash
  cd terraform/live/staging
  rm -rf .terragrunt-cache
  terragrunt init
  ```

**Issue**: "Import hanging"
- **Cause**: AWS API throttling or resource lock
- **Solution**: Wait for natural timeout, do NOT kill process
- **See**: [docs/terragrunt/troubleshooting.md](../docs/terragrunt/troubleshooting.md)

**Issue**: "State lock error"
- **Cause**: We don't use DynamoDB locking
- **Solution**: Ensure only one operation runs at a time

### Debug Mode

Enable verbose logging:

```bash
# Wrapper script verbose mode
./bootstrap/terragrunt-wrapper.sh staging plan --verbose

# Wrapper script debug mode (sets TF_LOG=DEBUG)
./bootstrap/terragrunt-wrapper.sh staging plan --debug

# Direct Terragrunt debug
cd terraform/live/staging
terragrunt plan --terragrunt-log-level debug
```

### View Generated Files

Terragrunt auto-generates configuration files:

```bash
cd terraform/live/staging/.terragrunt-cache/*/
ls -la *.tf

# View generated providers
cat providers.tf

# View generated backend
cat backend.tf

# View generated versions
cat versions.tf
```

## Best Practices

### ✅ Do

- **Always use Terragrunt wrapper** for consistency
- **Test in staging first** before production
- **Review plans carefully** before applying
- **Use verbose mode** for troubleshooting
- **Commit config.yaml changes** with descriptive messages
- **Keep one operation per environment** (no concurrent runs)

### ❌ Don't

- **DON'T run `terraform` directly** - always use `terragrunt`
- **DON'T edit generated files** (`.terragrunt-cache/`)
- **DON'T kill Terraform/Terragrunt processes** (corrupts state)
- **DON'T apply to prod without testing in staging**
- **DON'T commit `.terragrunt-cache/` or generated `.tf` files**
- **DON'T run multiple operations concurrently** (no state locking)

## Security Considerations

- **AWS Profiles**: Ensure profiles exist in `~/.aws/credentials`
- **IAM Permissions**: Hub account needs broad permissions
- **Cross-Account Roles**: Verify trust relationships
- **State Bucket**: Encrypted, versioned, private
- **Secrets**: Never commit credentials to Git

## Performance

- **Initialization**: ~2-3 minutes
- **Plan**: ~1-2 minutes
- **Apply (full)**: ~15-20 minutes (EKS cluster creation)
- **Apply (updates)**: ~3-5 minutes (configuration changes)
- **Destroy**: ~10-15 minutes

## Dependencies

**Required Tools**:
- Terragrunt >= 0.55.0
- Terraform >= 1.5.0, < 2.0.0
- AWS CLI v2
- kubectl >= 1.31.0
- helm >= 3.14.0
- jq (JSON processing)
- yq (YAML processing)

**Verify Installation**:
```bash
terragrunt --version
terraform version
aws --version
kubectl version --client
helm version
jq --version
yq --version
```

## Related Documentation

- [Terragrunt vs Terraform](../docs/terragrunt/vs-terraform.md)
- [Troubleshooting Guide](../docs/terragrunt/troubleshooting.md)
- [AWS Resource Deletion](../docs/terragrunt/aws-resource-deletion.md)
- [Main README](../README.md)
- [ArgoCD Documentation](../argocd/README.md)

---

**Last Updated**: October 7, 2025
**Maintained By**: Indiana University
