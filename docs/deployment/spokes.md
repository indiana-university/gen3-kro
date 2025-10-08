# Spoke Cluster Deployment Guide

This guide covers deploying spoke clusters using KRO (Kubernetes Resource Orchestrator) from the hub cluster.

## Overview

Spoke clusters are deployed declaratively using KRO ResourceGraphDefinitions (RGDs). The hub cluster manages spoke cluster lifecycle through GitOps.

## Prerequisites

- Hub cluster deployed and operational
- ArgoCD running on hub
- KRO controller installed on hub
- Shared KRO RGDs deployed

Verify prerequisites:
```bash
# Check ArgoCD
kubectl get pods -n argocd

# Check KRO controller
kubectl get pods -n kro-system

# Check RGD library
kubectl get resourcegraphdefinitions
```

## Architecture

```
Hub Cluster (EKS)
├── ArgoCD
│   └── Spoke Fleet ApplicationSet
│       ├── Monitors: config/spokes/*.yaml
│       └── Generates: Applications per spoke
├── KRO Controller
│   └── Watches: EKSCluster custom resources
└── Shared RGD Library
    ├── ekscluster.kro.run
    ├── vpc-network
    └── iam-roles

Spoke Clusters (EKS)
└── Created by KRO via AWS ACK controllers
```

## Create a New Spoke

### Step 1: Copy Template

```bash
# Create spoke configuration from template
cp config/spokes/template.yaml config/spokes/my-spoke.yaml
```

### Step 2: Edit Spoke Configuration

Edit `config/spokes/my-spoke.yaml`:

```yaml
name: my-spoke
aws_account_id: "123456789012"  # Target AWS account
aws_region: us-west-2
environment: staging

cluster:
  name: my-spoke-cluster
  version: "1.33"
  
network:
  vpc_cidr: "10.1.0.0/16"
  availability_zones:
    - us-west-2a
    - us-west-2b
    - us-west-2c
    
node_groups:
  - name: general
    instance_types:
      - t3.medium
    desired_size: 2
    min_size: 1
    max_size: 4
    disk_size: 50

addons:
  enable_cluster_autoscaler: true
  enable_metrics_server: true
  enable_efs_csi: false

argocd:
  repo_url: https://github.com/myorg/my-spoke-apps
  path: applications/base
  sync_wave: "3"
```

### Step 3: Commit Configuration

```bash
git add config/spokes/my-spoke.yaml
git commit -m "Add spoke cluster: my-spoke"
git push origin main
```

### Step 4: ArgoCD Auto-Sync

The spoke fleet ApplicationSet automatically detects the new configuration:

```bash
# Watch for new Application
kubectl get applications -n argocd -w

# Expected: my-spoke-infrastructure appears
```

### Step 5: Monitor Deployment

```bash
# Watch EKSCluster resource
kubectl get ekscluster my-spoke-cluster -w

# Check KRO graph status
kubectl describe ekscluster my-spoke-cluster

# View all resources in graph
kubectl get all -l kro.run/graph=my-spoke-cluster
```

**Expected Timeline**:
- VPC creation: ~2 minutes
- Subnet/NAT creation: ~3 minutes
- EKS control plane: ~15 minutes
- Node groups: ~5 minutes
- **Total: ~25 minutes**

### Step 6: Verify Spoke Cluster

```bash
# Update kubeconfig for spoke
aws eks update-kubeconfig \
  --name my-spoke-cluster \
  --region us-west-2 \
  --profile spoke-account-profile

# Verify nodes
kubectl get nodes

# Check system pods
kubectl get pods -A
```

## Multi-Account Setup

### Cross-Account IAM Roles

For spokes in different AWS accounts:

#### 1. Create Trust Relationship

In spoke account, create IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/hub-cluster-kro-role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

#### 2. Attach Policies

Attach AWS managed policies:
- `AmazonEKSClusterPolicy`
- `AmazonEKSServicePolicy`
- `AmazonVPCFullAccess` (or custom restricted policy)

#### 3. Update Spoke Config

```yaml
name: my-spoke
aws_account_id: "222222222222"
iam_role_arn: "arn:aws:iam::222222222222:role/spoke-provisioner-role"
```

### OIDC Provider Setup

After spoke cluster creation, configure OIDC:

```bash
# Get OIDC issuer
OIDC_ISSUER=$(aws eks describe-cluster \
  --name my-spoke-cluster \
  --region us-west-2 \
  --query "cluster.identity.oidc.issuer" \
  --output text)

# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url $OIDC_ISSUER \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list <thumbprint>
```

## Spoke Applications

### Deploy Applications to Spoke

Applications are managed via ArgoCD running on the hub.

#### Method 1: ArgoCD Applications (Recommended)

The spoke configuration includes an `argocd` section that creates an Application pointing to spoke-specific manifests:

```yaml
argocd:
  repo_url: https://github.com/myorg/my-spoke-apps
  path: applications/production
  target_revision: main
```

This Application is created automatically when the spoke is provisioned.

#### Method 2: Spoke Template Applications

Use the spoke-template structure:

```bash
# Copy spoke template
cp -r spokes/spoke-template spokes/my-spoke

# Edit applications
vim spokes/my-spoke/applications/base/kustomization.yaml

# Commit
git add spokes/my-spoke
git commit -m "Add spoke applications"
git push
```

### Application Sync Waves

Use sync waves to control deployment order:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  # Application spec
```

**Recommended Sync Waves**:
- `-3`: Infrastructure controllers
- `-1`: Namespaces, CRDs
- `0`: Core platform services
- `3`: Applications
- `5`: Monitoring/observability

## Modify Spoke Configuration

### Scale Node Groups

Edit `config/spokes/my-spoke.yaml`:

```yaml
node_groups:
  - name: general
    desired_size: 4  # Changed from 2
    min_size: 2
    max_size: 8
```

Commit and push - ArgoCD will reconcile changes.

### Upgrade Kubernetes Version

Edit `config/spokes/my-spoke.yaml`:

```yaml
cluster:
  version: "1.34"  # Upgrade from 1.33
```

⚠️ **Warning**: Upgrades trigger control plane updates. Review AWS EKS upgrade guide first.

### Add Node Group

```yaml
node_groups:
  - name: general
    instance_types: [t3.medium]
    desired_size: 2
    min_size: 1
    max_size: 4
  - name: compute    # New node group
    instance_types: [c5.xlarge]
    desired_size: 0
    min_size: 0
    max_size: 10
    labels:
      workload: compute-intensive
    taints:
      - key: workload
        value: compute
        effect: NoSchedule
```

## Troubleshooting

### Spoke Deployment Stuck

**Issue**: EKSCluster resource stuck in "Provisioning"

**Diagnosis**:
```bash
# Check KRO controller logs
kubectl logs -n kro-system deployment/kro-controller-manager

# Check ACK controller logs
kubectl logs -n ack-system deployment/ack-eks-controller

# Describe EKSCluster resource
kubectl describe ekscluster my-spoke-cluster
```

**Common Causes**:
- IAM permissions insufficient
- VPC CIDR conflicts
- Service limits exceeded

### Cross-Account Assume Role Fails

**Issue**: Cannot assume role in spoke account

**Solution**:
```bash
# Verify trust relationship
aws iam get-role --role-name spoke-provisioner-role --profile spoke-account

# Test assume role
aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/spoke-provisioner-role \
  --role-session-name test-session \
  --profile hub-account
```

### ArgoCD Cannot Sync Spoke

**Issue**: Application shows "Unknown" or "OutOfSync"

**Solution**:
```bash
# Check Application status
kubectl describe application my-spoke-infrastructure -n argocd

# Check ApplicationSet
kubectl describe applicationset spoke-fleet -n argocd

# Manual sync
argocd app sync my-spoke-infrastructure
```

### Nodes Not Joining

**Issue**: Nodes created but not joining cluster

**Solution**:
```bash
# Check node IAM role
aws eks describe-nodegroup \
  --cluster-name my-spoke-cluster \
  --nodegroup-name general

# Check aws-auth ConfigMap
kubectl get configmap aws-auth -n kube-system -o yaml

# Update if needed
kubectl edit configmap aws-auth -n kube-system
```

## Delete a Spoke

### Step 1: Remove Applications

```bash
# Delete Application resources first
kubectl delete application my-spoke-apps -n argocd
```

### Step 2: Delete Configuration

```bash
git rm config/spokes/my-spoke.yaml
git commit -m "Remove spoke cluster: my-spoke"
git push origin main
```

### Step 3: Monitor Deletion

```bash
# ArgoCD removes Application
kubectl get application my-spoke-infrastructure -n argocd

# KRO deletes EKSCluster resource
kubectl get ekscluster my-spoke-cluster -w

# Verify cleanup in AWS
aws eks list-clusters --region us-west-2
```

**Deletion Timeline**: ~15 minutes (node groups, then control plane, then VPC)

### Step 4: Clean Up IAM (Optional)

```bash
# Remove OIDC provider
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn <arn>

# Remove spoke IAM role (if cross-account)
aws iam delete-role --role-name spoke-provisioner-role
```

## Best Practices

### Naming Conventions

- Spoke names: `<team>-<environment>-<region>` (e.g., `data-prod-us-west-2`)
- Cluster names: Include spoke name for clarity
- Node groups: Descriptive names (`general`, `compute`, `gpu`)

### Resource Tagging

Add tags to all resources:

```yaml
tags:
  Environment: production
  Team: platform
  ManagedBy: kro
  CostCenter: engineering
```

### Security

- Use private endpoint access for production clusters
- Enable encryption at rest (EBS, secrets)
- Enable audit logging
- Use IRSA (IAM Roles for Service Accounts) for pod permissions

### Cost Optimization

- Use spot instances for non-critical workloads
- Enable cluster autoscaler
- Set appropriate node group min/max sizes
- Use graviton2/3 instances where possible

## Next Steps

- [Configure Applications](../applications.md)
- [Set up Multi-Tenancy](../multi-tenancy.md)
- [Configure Monitoring](../monitoring.md)
- [Disaster Recovery](../disaster-recovery.md)

## Reference

- [KRO Documentation](https://kro.run/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [ArgoCD ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
