# Gen3 KRO Units

This directory contains Terragrunt units that can be composed into stacks for deploying Gen3 infrastructure.

## Unit Dependency Flow

```
vpc → eks-cluster → eks-hub → eks-pod-identities → argo-deploy
                      ↓
                  iam-spoke
```

## Available Units

### 1. VPC (`units/vpc`)

Creates a VPC with public and private subnets for the EKS cluster.

**Dependencies:** None

**Outputs:**
- `vpc_id`
- `private_subnets`
- `public_subnets`
- `azs`

### 2. EKS Cluster (`units/eks-cluster`)

Creates an Amazon EKS cluster.

**Dependencies:**
- `vpc` (requires vpc_id and private_subnets)

**Outputs:**
- `cluster_name`
- `cluster_endpoint`
- `cluster_info`
- `account_id`

### 3. EKS Hub (`units/eks-hub`)

Creates ACK IAM roles and policies for the hub cluster.

**Dependencies:**
- `eks-cluster` (requires cluster_name)

**Outputs:**
- `ack_hub_roles`
- `account_id`

### 4. EKS Pod Identities (`units/eks-pod-identities`)

Manages all pod identity configurations for Kubernetes addons.

**Dependencies:**
- `eks-cluster` (requires cluster_name)
- `eks-hub` (requires ack_hub_roles)

**Outputs:**
- `aws_ebs_csi_role_arn`
- `external_secrets_role_arn`
- `aws_lb_controller_role_arn`
- `argocd_hub_role_arn`
- `ack_pod_identity_associations`

### 5. ArgoCD Deploy (`units/argo-deploy`)

Deploys ArgoCD to the cluster.

**Dependencies:**
- `eks-cluster` (requires cluster_info)
- `eks-pod-identities` (requires argocd_hub_role_arn)

### 6. IAM Spoke (`units/iam-spoke`)

Creates IAM roles for spoke accounts to allow ACK controllers to manage resources.

**Dependencies:**
- `eks-cluster` (requires cluster_info)
- `eks-hub` (requires ack_hub_roles)

**Outputs:**
- `account_id`
- `ack_spoke_role_arns`

## Usage

Units are designed to be consumed by stacks. Each unit references its module via Git URL for portability.

### Environment Variables

- `GEN3_KRO_VERSION`: Git reference (tag, branch, or commit) for module sources (default: "main")
- `AWS_REGION`: AWS region for deployment (default: "us-east-1")

### Example Stack Composition

```hcl
# In your stack configuration
include "root" {
  path = find_in_parent_folders()
}

# Deploy all units in order
dependencies {
  paths = [
    "../vpc",
    "../eks-cluster",
    "../eks-hub",
    "../eks-pod-identities",
    "../argo-deploy",
    "../iam-spoke"
  ]
}
```

## Customization

Each unit can be customized by:
1. Overriding inputs in the stack configuration
2. Creating a `common.hcl` file with shared variables
3. Using environment variables

## Module vs Unit

- **Modules** (`modules/`): Reusable Terraform code that provisions infrastructure
- **Units** (`units/`): Terragrunt configurations that reference modules and can be composed into stacks

Units are intentionally kept minimal and reference modules via Git URLs to ensure they can be distributed and consumed independently.
