# Terragrunt Deployment Guide

Learn how to deploy your own Gen3 KRO infrastructure using Terragrunt.

## Overview

This guide walks you through deploying your own hub-spoke infrastructure. Terragrunt provides DRY configurations and manages Terraform deployments across multiple environments.

**What You'll Deploy**:
- **Hub Cluster**: Control plane with ArgoCD, KRO, and ACK controllers
- **Spoke IAM** (optional): Cross-account IAM roles for spoke clusters

## Prerequisites

- Completed [Docker Setup](./setup-docker.md)
- AWS account with appropriate permissions
- AWS CLI configured with credentials
- S3 bucket for Terraform state (created during first deployment)
- DynamoDB table for state locking (optional but recommended)

## Directory Structure

Your deployment configurations live in the `live/` directory:

```
live/
└── aws/
    └── YOUR_REGION/
        ├── YOUR_CLUSTER/          # Your hub cluster
        │   └── terragrunt.hcl
        └── YOUR_SPOKE-iam/        # Optional: Spoke IAM
            └── terragrunt.hcl
```

## Hub Cluster Deployment

### 1. Customize Your Configuration

Navigate to your hub directory:

```bash
cd live/aws/us-east-1/YOUR_CLUSTER
```

Edit `terragrunt.hcl` to customize your deployment:

```hcl
terraform {
  source = "../../../../terraform/combinations/hub"
}

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  # Core - Customize these
  cluster_name    = "my-hub-cluster"          # Change this
  cluster_version = "1.32"
  region          = "us-east-1"               # Change if needed

  # VPC - Customize network ranges
  enable_vpc            = true
  vpc_name              = "my-hub-vpc"        # Change this
  vpc_cidr              = "10.0.0.0/16"       # Customize as needed
  availability_zones    = ["us-east-1a", "us-east-1b"]
  private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24"]

  # EKS - Adjust compute resources
  enable_eks_cluster = true
  cluster_compute_config = {
    min_size       = 2
    max_size       = 10
    desired_size   = 3
    instance_types = ["t3.large"]             # Change if needed
  }

  # ACK Controllers - Enable what you need
  enable_ack = true
  ack_configs = {
    ec2 = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-ec2-sa" }
    eks = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-eks-sa" }
    iam = { enable_pod_identity = true, namespace = "ack-system", service_account = "ack-iam-sa" }
  }

  # ArgoCD - Point to YOUR fork
  enable_argocd = true
  argocd_cluster = {
    metadata = {
      annotations = {
        hub_repo_url      = "https://github.com/YOUR_ORG/gen3-kro.git"  # Change this!
        hub_repo_revision = "main"
        hub_repo_basepath = "argocd"
      }
    }
  }

  # Tags
  tags = {
    Environment = "production"
    ManagedBy   = "Terragrunt"
    Project     = "My-Gen3-KRO"               # Customize
    Owner       = "your-email@example.com"    # Add your email
  }
}
```

### 2. Initialize Terragrunt

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

### 3. Plan Your Deployment

```bash
terragrunt plan
```

Review what will be created:
- VPC with subnets and NAT gateways
- EKS cluster control plane and node groups
- IAM roles for pod identities
- ArgoCD with bootstrap configuration
- ConfigMaps for cluster settings

### 4. Deploy Infrastructure

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

### 5. Connect to Your Cluster

```bash
# Update kubeconfig with your cluster name
aws eks update-kubeconfig --name my-hub-cluster --region us-east-1

# Verify connection
kubectl get nodes
```

### 6. Verify Deployment

Check that everything deployed successfully:

```bash
# Check cluster nodes (should see 3 nodes in Ready state)
kubectl get nodes

# Check ArgoCD applications (should be Synced/Healthy)
kubectl get applications -n argocd

# Check ACK controllers (should be Running)
kubectl get pods -n ack-system

# Check KRO controller (deployed by ArgoCD)
kubectl get pods -n kro-system

# Check ResourceGraphDefinitions
kubectl get rgd
```

Expected output shows all pods running and applications synced.

## Spoke IAM Deployment (Optional)

If you're deploying spoke clusters in different AWS accounts, you'll need to provision IAM roles first.

### 1. Navigate to Spoke IAM Directory

```bash
cd live/aws/us-east-1/YOUR_SPOKE-iam
```

### 2. Customize Spoke Configuration

Edit `terragrunt.hcl`:

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

Create policy files for your spoke:

```bash
# Create directories
mkdir -p iam/gen3/YOUR_SPOKE/acks/{ec2,eks,iam}

# Create EC2 policy
cat > iam/gen3/YOUR_SPOKE/acks/ec2/internal-policy.json <<EOF
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
cat > iam/gen3/YOUR_SPOKE/acks/eks/internal-policy.json <<EOF
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
cat > iam/gen3/YOUR_SPOKE/acks/iam/internal-policy.json <<EOF
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

After spoke IAM is created, update your hub to attach cross-account policies.

Edit `live/aws/us-east-1/YOUR_CLUSTER/terragrunt.hcl`:

```hcl
dependency "my_spoke_iam" {
  config_path = "../YOUR_SPOKE-iam"
  skip_outputs = false
}

inputs = {
  # ... existing config ...

  enable_multi_acct = true
  spoke_arn_inputs = {
    my_spoke = {
      for svc, arn in dependency.my_spoke_iam.outputs.spoke_role_arns :
      svc => { role_arn = arn }
    }
  }
}
```

Apply changes:

```bash
cd ../YOUR_CLUSTER
terragrunt apply
```

This attaches cross-account AssumeRole policies to your hub pod identities.

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
