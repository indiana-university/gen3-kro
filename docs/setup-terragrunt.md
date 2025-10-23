# Terragrunt Deployment Guide

This guide explains how to deploy the Gen3 KRO platform infrastructure using Terragrunt.

## Overview

Terragrunt is a thin wrapper for Terraform that provides DRY (Don't Repeat Yourself) configurations and additional tooling for managing infrastructure at scale. The Gen3 KRO platform uses Terragrunt to deploy:

- **Hub Cluster**: Central control plane with ArgoCD, KRO, and ACK controllers
- **Spoke IAM**: Cross-account IAM roles for spoke clusters

## Prerequisites

- Completed [Docker Setup](./setup-docker.md)
- AWS account with appropriate permissions
- AWS CLI configured with credentials
- S3 bucket for Terraform state (created during first deployment)
- DynamoDB table for state locking (optional but recommended)

## Directory Structure

```
live/
└── aws/
    └── us-east-1/
        ├── gen3-kro-hub/          # Hub cluster deployment
        │   └── terragrunt.hcl
        └── spoke1-iam/            # Spoke IAM deployment
            └── terragrunt.hcl
```

## Hub Cluster Deployment

### 1. Navigate to Hub Directory

```bash
cd /workspaces/gen3-kro/live/aws/us-east-1/gen3-kro-hub
```

### 2. Review Configuration

Inspect `terragrunt.hcl`:

```hcl
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
    min_size       = 2
    max_size       = 10
    desired_size   = 3
    instance_types = ["t3.large"]
  }

  # ACK Controllers
  enable_ack = true
  ack_configs = {
    ec2 = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-ec2-sa" }
    eks = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-eks-sa" }
    iam = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-iam-sa" }
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

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "Gen3-KRO"
  }
}
```

### 3. Initialize Terragrunt

```bash
terragrunt init
```

This will:
- Initialize Terraform backend (S3 + DynamoDB)
- Download Terraform modules
- Download provider plugins

Expected output:
```
Initializing the backend...
Initializing modules...
Initializing provider plugins...
Terraform has been successfully initialized!
```

### 4. Plan Infrastructure

```bash
terragrunt plan
```

This generates an execution plan showing what Terraform will create.

Review the plan carefully:
- **VPC resources**: VPC, subnets, route tables, NAT gateways
- **EKS cluster**: Control plane, node group, OIDC provider
- **IAM roles**: Pod identity roles for ACK controllers and addons
- **ArgoCD**: Helm release, cluster secret, bootstrap ApplicationSets
- **ConfigMaps**: Hub configuration for ArgoCD

### 5. Apply Infrastructure

```bash
terragrunt apply
```

Terraform will prompt for confirmation. Review the plan and type `yes`.

**Duration**: ~20-30 minutes
- VPC: ~2 minutes
- EKS cluster: ~15-20 minutes
- Pod identities: ~2-3 minutes
- ArgoCD: ~3-5 minutes

**Output**:
```
Apply complete! Resources: 78 added, 0 changed, 0 destroyed.

Outputs:

ack_role_arns = {
  "ec2" = "arn:aws:iam::123456789012:role/gen3-kro-hub-ec2"
  "eks" = "arn:aws:iam::123456789012:role/gen3-kro-hub-eks"
  "iam" = "arn:aws:iam::123456789012:role/gen3-kro-hub-iam"
}
cluster_endpoint = "https://XXXXXXXX.gr7.us-east-1.eks.amazonaws.com"
cluster_name = "gen3-kro-hub"
vpc_id = "vpc-0123456789abcdef0"
```

### 6. Connect to Cluster

```bash
# Update kubeconfig
aws eks update-kubeconfig --name gen3-kro-hub --region us-east-1

# Verify connection
kubectl get nodes

# Check ArgoCD
kubectl get applications -n argocd
kubectl get applicationsets -n argocd
```

### 7. Verify Deployment

Run verification steps:

```bash
# Check nodes are ready
kubectl get nodes
# Expected: 3 nodes in Ready state

# Check ArgoCD applications
kubectl get applications -n argocd
# Expected: Multiple applications in Synced/Healthy state

# Check ACK controllers
kubectl get pods -n ack-system
# Expected: ACK controller pods running

# Check KRO controller (deployed by ArgoCD Wave 0)
kubectl get pods -n kro-system
# Expected: KRO controller pods running

# Check ResourceGraphDefinitions (deployed by ArgoCD Wave 1)
kubectl get rgd
# Expected: VPC, EKS, IAM RGDs
```

## Spoke IAM Deployment

After the hub is deployed, provision IAM roles for spoke clusters.

### 1. Navigate to Spoke IAM Directory

```bash
cd /workspaces/gen3-kro/live/aws/us-east-1/spoke1-iam
```

### 2. Review Configuration

Inspect `terragrunt.hcl`:

```hcl
terraform {
  source = "../../../../terraform/combinations/spoke"
}

include "root" {
  path = find_in_parent_folders()
}

# Get hub outputs
dependency "hub" {
  config_path = "../gen3-kro-hub"

  mock_outputs = {
    ack_role_arns = {
      ec2 = "arn:aws:iam::123456789012:role/hub-ack-ec2"
      eks = "arn:aws:iam::123456789012:role/hub-ack-eks"
      iam = "arn:aws:iam::123456789012:role/hub-ack-iam"
    }
  }
}

inputs = {
  # Core
  spoke_alias  = "spoke1"
  cluster_name = "spoke1-cluster"
  region       = "us-east-1"

  # ACK Controllers
  ack_configs = {
    ec2 = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["ec2"]
      override_arn    = ""  # Empty = create role
      namespace       = "ack-system"
      service_account = "ack-ec2-sa"
    }
    eks = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["eks"]
      override_arn    = ""
      namespace       = "ack-system"
      service_account = "ack-eks-sa"
    }
    iam = {
      hub_role_arn    = dependency.hub.outputs.ack_role_arns["iam"]
      override_arn    = ""
      namespace       = "ack-system"
      service_account = "ack-iam-sa"
    }
  }

  # IAM
  iam_base_path = "gen3"

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "Gen3-KRO"
    Spoke       = "spoke1"
  }
}
```

### 3. Create IAM Policies

Before deploying, create IAM policy files:

```bash
# Create directories
mkdir -p ../../../../iam/gen3/spoke1/acks/{ec2,eks,iam}

# Create EC2 policy
cat > ../../../../iam/gen3/spoke1/acks/ec2/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateTags",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create EKS policy
cat > ../../../../iam/gen3/spoke1/acks/eks/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:Describe*",
        "eks:List*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Create IAM policy
cat > ../../../../iam/gen3/spoke1/acks/iam/internal-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:GetPolicy",
        "iam:ListAttachedRolePolicies"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

### 4. Initialize, Plan, Apply

```bash
terragrunt init
terragrunt plan
terragrunt apply
```

**Duration**: ~1-2 minutes (IAM only)

**Output**:
```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:

spoke_role_arns = {
  "ec2" = "arn:aws:iam::987654321098:role/spoke1-ec2"
  "eks" = "arn:aws:iam::987654321098:role/spoke1-eks"
  "iam" = "arn:aws:iam::987654321098:role/spoke1-iam"
}
```

### 5. Update Hub with Spoke ARNs

After spoke IAM is created, update the hub to attach cross-account policies.

Edit `live/aws/us-east-1/gen3-kro-hub/terragrunt.hcl`:

```hcl
dependency "spoke1_iam" {
  config_path = "../spoke1-iam"
  skip_outputs = false
}

inputs = {
  # ... existing config ...

  enable_multi_acct = true
  spoke_arn_inputs = {
    spoke1 = {
      for svc, arn in dependency.spoke1_iam.outputs.spoke_role_arns :
      svc => { role_arn = arn }
    }
  }
}
```

Apply changes:

```bash
cd ../gen3-kro-hub
terragrunt apply
```

This attaches AssumeRole policies to hub pod identities.

## Verification and Validation

### Verify ArgoCD Sync

```bash
# Check ApplicationSets
kubectl get applicationsets -n argocd

# Check Applications
kubectl get applications -n argocd

# Check sync status
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status
```

All applications should show:
- SYNC: `Synced`
- HEALTH: `Healthy`

### Verify IAM Roles

```bash
# List hub roles
aws iam list-roles --query 'Roles[?contains(RoleName, `gen3-kro-hub`)]'

# List spoke roles
aws iam list-roles --query 'Roles[?contains(RoleName, `spoke1`)]'

# Verify trust policy
aws iam get-role --role-name spoke1-ec2 --query 'Role.AssumeRolePolicyDocument'
```

### Verify Cross-Account Policies

```bash
# Check hub role policies
aws iam list-attached-role-policies --role-name gen3-kro-hub-ec2

# Verify AssumeRole policy
aws iam get-role-policy --role-name gen3-kro-hub-ec2 --policy-name cross-account-ec2
```

## Terragrunt Commands

### Common Operations

```bash
# Initialize
terragrunt init

# Plan changes
terragrunt plan

# Apply changes
terragrunt apply

# Show outputs
terragrunt output

# Destroy infrastructure
terragrunt destroy

# Format HCL files
terragrunt hclfmt

# Validate configuration
terragrunt validate
```

### Advanced Commands

```bash
# Plan with full output
terragrunt plan -out=tfplan

# Apply without prompting
terragrunt apply -auto-approve

# Destroy specific resource
terragrunt destroy -target=module.vpc

# Refresh state
terragrunt refresh

# Show state
terragrunt show

# Import existing resource
terragrunt import module.vpc.aws_vpc.this vpc-xxxxx
```

### Multi-Environment Commands

```bash
# Run plan for all environments
terragrunt run-all plan

# Apply changes to all environments
terragrunt run-all apply

# Destroy all environments
terragrunt run-all destroy
```

## State Management

### Remote State Configuration

Terragrunt automatically configures remote state in S3:

```hcl
# root terragrunt.hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = "gen3-kro-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### State Operations

```bash
# List state resources
terragrunt state list

# Show specific resource
terragrunt state show module.vpc.aws_vpc.this

# Move resource in state
terragrunt state mv module.old.resource module.new.resource

# Remove resource from state
terragrunt state rm module.unwanted.resource

# Pull current state
terragrunt state pull > current.tfstate

# Push state (use with caution!)
terragrunt state push updated.tfstate
```

## Troubleshooting

### State Lock Error

**Symptom**:
```
Error: Error acquiring the state lock
```

**Solution**:
```bash
# Identify lock
aws dynamodb get-item \
  --table-name terraform-locks \
  --key '{"LockID":{"S":"gen3-kro-terraform-state/live/aws/us-east-1/gen3-kro-hub/terraform.tfstate-md5"}}'

# Force unlock (if safe to do so)
terragrunt force-unlock <lock-id>
```

### Dependency Not Found

**Symptom**:
```
Error: Could not load dependency outputs
```

**Solution**:
```bash
# Ensure dependency is applied
cd <dependency-path>
terragrunt apply

# Return to original directory
cd -
terragrunt plan
```

### Module Not Found

**Symptom**:
```
Error: Module not found
```

**Solution**:
```bash
# Clear cache
rm -rf .terragrunt-cache

# Re-initialize
terragrunt init
```

### Provider Version Conflict

**Symptom**:
```
Error: Incompatible provider version
```

**Solution**:
```bash
# Upgrade providers
terragrunt init -upgrade

# Lock provider versions
terragrunt providers lock
```

## Best Practices

### 1. Always Run Init After Changes

```bash
# After updating Terraform version
terragrunt init -upgrade

# After adding new modules
terragrunt init

# After changing backend config
terragrunt init -reconfigure
```

### 2. Use Plan Before Apply

```bash
# Always review changes
terragrunt plan

# Save plan
terragrunt plan -out=tfplan

# Apply saved plan
terragrunt apply tfplan
```

### 3. Use Version Constraints

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

### 4. Tag All Resources

```hcl
inputs = {
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "Gen3-KRO"
    Owner       = "team@example.com"
    CostCenter  = "12345"
  }
}
```

### 5. Use Workspaces for Environments

```bash
# Create workspace
terraform workspace new staging

# Switch workspace
terraform workspace select staging

# List workspaces
terraform workspace list
```

## Continuous Deployment

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Terraform Deploy

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Terragrunt
        run: |
          wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.48.0/terragrunt_linux_amd64
          chmod +x terragrunt_linux_amd64
          sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Terragrunt Init
        working-directory: live/aws/us-east-1/gen3-kro-hub
        run: terragrunt init

      - name: Terragrunt Plan
        working-directory: live/aws/us-east-1/gen3-kro-hub
        run: terragrunt plan

      - name: Terragrunt Apply
        if: github.ref == 'refs/heads/main'
        working-directory: live/aws/us-east-1/gen3-kro-hub
        run: terragrunt apply -auto-approve
```

## See Also

- [Docker Setup Guide](./setup-docker.md)
- [Adding Cluster Addons](./add-cluster-addons.md)
- [Hub Combination](../terraform/combinations/hub/README.md)
- [Spoke Combination](../terraform/combinations/spoke/README.md)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/docs/)
