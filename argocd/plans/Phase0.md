# Phase 0: Foundation Setup


---

## Overview

Phase 0 establishes all prerequisites for the Gen3 KRO deployment. This phase involves no infrastructure deployment but ensures all configuration, IAM roles, and supporting services are in place.

---

## Objectives

1. ✅ Create all IAM roles for ACK controllers (hub + spokes)
2. ✅ Configure Terraform state management
3. ✅ Set up AWS Secrets Manager for cluster credentials
4. ✅ Populate all configuration files with environment-specific values
5. ✅ Validate repository structure and file paths
6. ✅ Prepare monitoring and logging infrastructure

---

## Prerequisites

- AWS accounts (hub + spoke accounts)
- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0 installed
- Git repository cloned locally
- Administrative access to AWS accounts

---

## Task Breakdown

### Task 0.1: IAM Role Creation (6-8 hours)

**Objective**: Create IAM roles for all ACK controllers with IRSA trust policies

**ACK Controllers Requiring IAM Roles** (15 total):
1. cloudtrail
2. cloudwatchlogs
3. ec2
4. efs
5. eks
6. iam
7. kms
8. opensearchservice
9. rds
10. route53
11. s3
12. secretsmanager
13. sns
14. sqs
15. wafv2

**Environments**:
- Hub (control plane)
- Spoke1 (workload cluster)

**Total Roles**: 30 (15 controllers × 2 environments)

#### Step 0.1.1: Create IAM Role Template

Create a Terraform module for ACK controller roles:

```bash
mkdir -p terraform/modules/ack-iam-roles
```

**File**: `terraform/modules/ack-iam-roles/main.tf`
```hcl
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https://)"
  type        = string
}

variable "controller_name" {
  description = "ACK controller name (e.g., ec2, eks, iam)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for controller"
  type        = string
  default     = "ack-system"
}

# IAM Role for ACK Controller
resource "aws_iam_role" "ack_controller" {
  name = "${var.cluster_name}-ack-${var.controller_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:ack-${var.controller_name}-controller"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-ack-${var.controller_name}"
    Controller  = var.controller_name
    Cluster     = var.cluster_name
    ManagedBy   = "terraform"
  }
}

# Attach AWS managed policy for controller
resource "aws_iam_role_policy_attachment" "ack_controller" {
  role       = aws_iam_role.ack_controller.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSControllerForKubernetes${title(var.controller_name)}Policy"
}

output "role_arn" {
  value = aws_iam_role.ack_controller.arn
}

output "role_name" {
  value = aws_iam_role.ack_controller.name
}
```

#### Step 0.1.2: Create Hub IAM Roles

**File**: `terraform/live/staging/hub-ack-roles/terragrunt.hcl`
```hcl
terraform {
  source = "../../../modules/ack-iam-roles"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "hub_cluster" {
  config_path = "../hub-cluster"
}

locals {
  controllers = [
    "cloudtrail", "cloudwatchlogs", "ec2", "efs", "eks", "iam", "kms",
    "opensearchservice", "rds", "route53", "s3", "secretsmanager",
    "sns", "sqs", "wafv2"
  ]
}

# Generate module calls for each controller
generate "controllers" {
  path      = "controllers.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    %{for controller in local.controllers~}
    module "ack_${controller}" {
      source = "../../../modules/ack-iam-roles"

      cluster_name      = dependency.hub_cluster.outputs.cluster_name
      oidc_provider_arn = dependency.hub_cluster.outputs.oidc_provider_arn
      oidc_provider_url = dependency.hub_cluster.outputs.oidc_provider_url
      controller_name   = "${controller}"
      namespace         = "ack-system"
    }

    output "${controller}_role_arn" {
      value = module.ack_${controller}.role_arn
    }
    %{endfor~}
  EOF
}
```

#### Step 0.1.3: Document Role ARNs

Create a script to extract role ARNs after creation:

**File**: `bootstrap/scripts/extract-iam-roles.sh`
```bash
#!/bin/bash
set -e

ENVIRONMENT=$1
CLUSTER_TYPE=$2  # hub or spoke1

if [[ -z "$ENVIRONMENT" ]] || [[ -z "$CLUSTER_TYPE" ]]; then
  echo "Usage: $0 <environment> <cluster_type>"
  echo "Example: $0 staging hub"
  exit 1
fi

echo "Extracting IAM role ARNs for ${CLUSTER_TYPE} in ${ENVIRONMENT}..."

cd terraform/live/${ENVIRONMENT}/${CLUSTER_TYPE}-ack-roles

terragrunt output -json | jq -r 'to_entries[] | select(.key | endswith("_role_arn")) | "\(.key): \(.value.value)"' > ../../../../argocd/${CLUSTER_TYPE}/addons/role-arns.txt

echo "Role ARNs saved to argocd/${CLUSTER_TYPE}/addons/role-arns.txt"
cat ../../../../argocd/${CLUSTER_TYPE}/addons/role-arns.txt
```

#### Step 0.1.4: Validation

```bash
# Validate IAM roles exist
aws iam list-roles | jq -r '.Roles[] | select(.RoleName | startswith("hub-ack-")) | .RoleName'

# Validate trust policies
aws iam get-role --role-name hub-ack-ec2 | jq '.Role.AssumeRolePolicyDocument'

# Count roles
aws iam list-roles | jq '[.Roles[] | select(.RoleName | startswith("hub-ack-"))] | length'
# Expected: 15
```

**Checklist**:
- [ ] All 15 hub IAM roles created
- [ ] All 15 spoke1 IAM roles created
- [ ] Trust policies include OIDC provider
- [ ] AWS managed policies attached
- [ ] Role ARNs documented

---

### Task 0.2: Terraform State Configuration (2 hours)

**Objective**: Set up remote state backend for Terraform

#### Step 0.2.1: Create S3 Bucket for State

```bash
aws s3api create-bucket \
  --bucket gen3-kro-terraform-state-staging \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket gen3-kro-terraform-state-staging \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket gen3-kro-terraform-state-staging \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

#### Step 0.2.2: Create DynamoDB Table for Locking

```bash
aws dynamodb create-table \
  --table-name gen3-kro-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

#### Step 0.2.3: Configure Terragrunt

**File**: `terraform/root.hcl`
```hcl
remote_state {
  backend = "s3"

  config = {
    bucket         = "gen3-kro-terraform-state-${local.environment}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "gen3-kro-terraform-locks"
  }

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
}

locals {
  environment = get_env("ENVIRONMENT", "staging")
}
```

**Checklist**:
- [ ] S3 bucket created
- [ ] Versioning enabled
- [ ] Encryption enabled
- [ ] DynamoDB table created
- [ ] Terragrunt configured

---

### Task 0.3: AWS Secrets Manager Setup (2 hours)

**Objective**: Store sensitive configuration in AWS Secrets Manager

#### Step 0.3.1: Create Secrets for ArgoCD Cluster Registration

```bash
# Hub cluster admin credentials
aws secretsmanager create-secret \
  --name staging/hub/argocd-secret \
  --description "ArgoCD admin credentials for hub cluster" \
  --secret-string '{
    "username": "admin",
    "password": "CHANGE_ME_ON_FIRST_LOGIN"
  }' \
  --region us-west-2

# Spoke1 cluster credentials (will be populated by KRO)
aws secretsmanager create-secret \
  --name staging/spoke1/argocd-secret \
  --description "ArgoCD cluster registration for spoke1" \
  --secret-string '{}' \
  --region us-west-2
```

#### Step 0.3.2: Create External Secrets Configuration

**File**: `argocd/hub/addons/values.yaml` (add external-secrets config)
```yaml
external-secrets:
  namespace: external-secrets-system
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/hub-external-secrets"
  secretStore:
    provider: aws
    region: us-west-2
```

**Checklist**:
- [ ] ArgoCD secrets created
- [ ] IAM role for external-secrets created
- [ ] Secret access policies configured

---

### Task 0.4: Configuration File Population (4-6 hours)

**Objective**: Populate all `values.yaml` files with environment-specific values

#### Step 0.4.1: Update Hub Addons Values

**File**: `argocd/hub/addons/values.yaml`

```bash
# Use the extract-iam-roles.sh script output
# Replace all placeholder ARNs with real values

# Example:
cloudtrail:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/hub-ack-cloudtrail"
  # ... repeat for all 15 controllers
```

#### Step 0.4.2: Create Catalog File

**File**: `argocd/hub/addons/catalog.yaml`

Populate with exact chart versions (see Proposal.md Section 2.2 for full list)

#### Step 0.4.3: Update Spoke Infrastructure Values

**File**: `argocd/spokes/spoke1/infrastructure/values.yaml`

```yaml
apiVersion: v1alpha1
kind: EksCluster
metadata:
  name: spoke1-cluster
spec:
  name: spoke1
  tenant: auto1
  environment: staging
  region: us-west-2
  k8sVersion: "1.32"
  accountId: "987654321098"  # REPLACE WITH REAL SPOKE ACCOUNT ID
  managementAccountId: "123456789012"  # REPLACE WITH REAL HUB ACCOUNT ID
  adminRoleName: "Admin"
  fleetSecretManagerSecretNameSuffix: "argocd-secret"
  domainName: "spoke1.staging.example.com"  # REPLACE WITH REAL DOMAIN
  vpc:
    vpcCidr: "10.1.0.0/16"
    publicSubnet1Cidr: "10.1.1.0/24"
    publicSubnet2Cidr: "10.1.2.0/24"
    privateSubnet1Cidr: "10.1.11.0/24"
    privateSubnet2Cidr: "10.1.12.0/24"
```

**Checklist**:
- [ ] Hub catalog.yaml complete with all 18 addons
- [ ] Hub enablement.yaml configured
- [ ] Hub values.yaml with all 15 ACK role ARNs
- [ ] Spoke1 enablement.yaml configured
- [ ] Spoke1 values.yaml with spoke-specific role ARNs
- [ ] Spoke1 infrastructure values with real account IDs

---

### Task 0.5: Repository Validation (2 hours)

**Objective**: Validate all files and paths are correct

#### Step 0.5.1: Validate YAML Syntax

```bash
# Validate all YAML files
find argocd/ -name "*.yaml" -exec yamllint {} \;

# Validate Kubernetes manifests
find argocd/bootstrap/ -name "*.yaml" -exec kubectl apply --dry-run=client -f {} \;
```

#### Step 0.5.2: Validate Kustomizations

```bash
# Test shared instances kustomization
kustomize build argocd/shared/instances/

# Test spoke1 infrastructure kustomization
kustomize build argocd/spokes/spoke1/infrastructure/
```

#### Step 0.5.3: Validate File Paths

```bash
# Check expected files exist
test -f argocd/bootstrap/addons.yaml && echo "✓ addons.yaml"
test -f argocd/bootstrap/graphs.yaml && echo "✓ graphs.yaml"
test -f argocd/bootstrap/graph-instances.yaml && echo "✓ graph-instances.yaml"
test -f argocd/bootstrap/gen3-instances.yaml && echo "✓ gen3-instances.yaml"

# Check shared graphs
ls argocd/shared/graphs/aws/*.yaml | wc -l
# Expected: 6 RGD files

# Check spoke structure
test -d argocd/spokes/spoke1/addons && echo "✓ spoke1 addons"
test -d argocd/spokes/spoke1/infrastructure && echo "✓ spoke1 infrastructure"
```

#### Step 0.5.4: Git Pre-Commit Hooks

```bash
# Install pre-commit hooks
./bootstrap/scripts/install-git-hooks.sh

# Test pre-commit validation
git add .
git commit -m "test commit" --dry-run
```

**Checklist**:
- [ ] All YAML files valid
- [ ] Kustomizations build successfully
- [ ] All expected files present
- [ ] Git hooks installed

---

### Task 0.6: Monitoring and Logging Setup (2-3 hours)

**Objective**: Prepare monitoring infrastructure

#### Step 0.6.1: CloudWatch Log Groups

```bash
# Create log groups for hub cluster
aws logs create-log-group \
  --log-group-name /aws/eks/hub-staging/cluster \
  --region us-west-2

aws logs create-log-group \
  --log-group-name /aws/eks/hub-staging/application \
  --region us-west-2

# Set retention
aws logs put-retention-policy \
  --log-group-name /aws/eks/hub-staging/cluster \
  --retention-in-days 30 \
  --region us-west-2
```

#### Step 0.6.2: SNS Topics for Alerts

```bash
# Create SNS topic for deployment alerts
aws sns create-topic \
  --name gen3-kro-deployment-alerts \
  --region us-west-2

# Subscribe email
aws sns subscribe \
  --topic-arn arn:aws:sns:us-west-2:123456789012:gen3-kro-deployment-alerts \
  --protocol email \
  --notification-endpoint team@example.com
```

**Checklist**:
- [ ] CloudWatch log groups created
- [ ] SNS topics created
- [ ] Alert subscriptions configured

---

## Validation and Sign-Off

### Pre-Phase 1 Checklist

- [ ] All 30 IAM roles created (15 hub + 15 spoke1)
- [ ] Terraform state backend configured and tested
- [ ] AWS Secrets Manager secrets created
- [ ] All `catalog.yaml` files populated
- [ ] All `enablement.yaml` files configured
- [ ] All `values.yaml` files with real ARNs
- [ ] Spoke infrastructure values with real account IDs
- [ ] All YAML files validate successfully
- [ ] Kustomizations build successfully
- [ ] Git hooks installed
- [ ] Monitoring infrastructure ready

### Validation Commands

```bash
# IAM Role Count
aws iam list-roles | jq '[.Roles[] | select(.RoleName | contains("ack-"))] | length'
# Expected: 30

# Secrets Manager
aws secretsmanager list-secrets | jq '.SecretList[] | select(.Name | contains("argocd-secret")) | .Name'
# Expected: 2 secrets

# File Validation
find argocd/ -name "*.yaml" | wc -l
# Expected: 50+ files

# Kustomize Build
kustomize build argocd/spokes/spoke1/infrastructure/ | grep "kind: EksCluster"
# Expected: EksCluster manifest
```

### Sign-Off

**Prepared By**: _______________
**Reviewed By**: _______________
**Approved By**: _______________

---

## Troubleshooting

### Issue: IAM Role Creation Fails

**Symptoms**: Terraform error creating IAM role

**Solutions**:
1. Check AWS credentials: `aws sts get-caller-identity`
2. Verify OIDC provider exists: `aws iam list-open-id-connect-providers`
3. Check IAM permissions: Ensure user has `iam:CreateRole` permission

### Issue: Kustomize Build Fails

**Symptoms**: `kustomize build` returns error

**Solutions**:
1. Check base path: Ensure `bases` points to correct directory
2. Validate patch syntax: YAML indentation must be exact
3. Test individual files: `kubectl apply --dry-run=client -f <file>`

### Issue: YAML Validation Fails

**Symptoms**: `yamllint` or `kubectl` errors

**Solutions**:
1. Fix indentation: Use 2 spaces, no tabs
2. Validate quotes: Use single quotes for template strings
3. Check Go template syntax: `{{ }}` must be properly escaped

---

## Next Steps

Upon completion of Phase 0:
1. Schedule Phase 1 kickoff meeting
2. Review Phase 1 plan with team
3. Assign Phase 1 tasks
4. Proceed to [Phase 1: Hub Bootstrap](./Phase1.md)

---

---

**Owner**: BabasanmiAdeyemi  
**Username**: boadeyem  
**Team**: RDS Team
