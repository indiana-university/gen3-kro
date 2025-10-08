# Hub Cluster Deployment Guide

This guide covers deploying the hub cluster infrastructure using Terraform/Terragrunt.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- Terragrunt >= 0.55.0
- kubectl >= 1.31.0
- Git

## Configuration

### 1. Edit Main Configuration

Edit `config/config.yaml`:

```yaml
hub:
  alias: "my-hub"
  aws_profile: "my-aws-profile"
  aws_region: "us-east-1"
  cluster_name: "my-hub-cluster"
  kubernetes_version: "1.33"
  vpc_name: "my-hub-vpc"

paths:
  terraform_state_bucket: "my-terraform-state-bucket"
  
addons:
  enable_metrics_server: true
  enable_kyverno: true
  enable_argocd: true
  enable_kro: true
  enable_ack_iam: true
```

### 2. Configure Environment

Edit `config/environments/staging.yaml` or `prod.yaml`:

```yaml
environment: staging
cluster_name_suffix: staging
kubernetes_version: "1.33"
vpc_cidr: "10.0.0.0/16"
```

## Deployment Steps

### Step 1: Validate Configuration

```bash
./bootstrap/terragrunt-wrapper.sh staging validate
```

**Expected Output**:
```
✓ Configuration validation passed
✓ Configuration is valid
```

### Step 2: Plan Infrastructure

```bash
./bootstrap/terragrunt-wrapper.sh staging plan
```

This creates an execution plan showing all resources to be created:
- VPC and networking components
- EKS cluster
- IAM roles and policies
- ArgoCD installation
- KMS keys for encryption

Review the plan carefully before proceeding.

### Step 3: Apply Infrastructure

```bash
./bootstrap/terragrunt-wrapper.sh staging apply
```

**Duration**: Approximately 20-30 minutes

**Resources Created**:
- VPC with public/private subnets
- NAT Gateways
- EKS control plane
- EKS node groups
- IAM roles for service accounts
- ArgoCD via Helm
- KMS encryption keys

### Step 4: Connect to Cluster

```bash
# Update kubeconfig
./bootstrap/scripts/connect-cluster.sh staging

# Verify connectivity
kubectl get nodes

# Check ArgoCD installation
kubectl get pods -n argocd
```

### Step 5: Access ArgoCD UI

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login: admin / <password-from-above>
```

## Bootstrap Hub GitOps

### Step 6: Apply Hub Bootstrap

```bash
# Apply hub ArgoCD bootstrap
kubectl apply -k hub/argocd/bootstrap/overlays/staging

# Wait for app-of-apps
kubectl wait --for=condition=available --timeout=300s \
  -n argocd app/hub-addons
```

### Step 7: Verify Hub Addons

```bash
# Check applications
kubectl get applications -n argocd

# Expected applications:
# - hub-addons (app-of-apps)
# - kro-controller
# - kro-rgds
```

### Step 8: Verify KRO Installation

```bash
# Check KRO controller
kubectl get pods -n kro-system

# Check RGD definitions
kubectl get resourcegraphdefinitions

# Expected RGDs:
# - ekscluster.kro.run
# - vpc-network
# - iam-roles
```

## Post-Deployment

### Deploy Fleet Management

```bash
# Apply spoke fleet ApplicationSet
kubectl apply -f hub/argocd/fleet/spoke-fleet-appset.yaml

# Verify
kubectl get applicationsets -n argocd
```

### Configure Monitoring (Optional)

```bash
# Enable Prometheus/Grafana if desired
kubectl apply -f monitoring/
```

## Troubleshooting

### Plan Fails

**Issue**: Terraform plan fails with authentication errors

**Solution**:
```bash
# Verify AWS credentials
aws sts get-caller-identity --profile my-aws-profile

# Refresh credentials if needed
aws sso login --profile my-aws-profile
```

### Apply Hangs

**Issue**: Terragrunt apply hangs during EKS creation

**Solution**:
- EKS creation takes 15-20 minutes - this is normal
- Check AWS console for cluster status
- Check CloudFormation stacks for any failures

### Cannot Connect to Cluster

**Issue**: kubectl commands fail after deployment

**Solution**:
```bash
# Verify cluster exists
aws eks list-clusters --region us-east-1

# Update kubeconfig manually
aws eks update-kubeconfig --name my-hub-cluster --region us-east-1

# Check IAM permissions
aws eks describe-cluster --name my-hub-cluster --region us-east-1
```

### ArgoCD Not Starting

**Issue**: ArgoCD pods stuck in Pending or CrashLoopBackOff

**Solution**:
```bash
# Check pod status
kubectl describe pod -n argocd <pod-name>

# Check node resources
kubectl top nodes

# Scale up nodes if needed
```

## Upgrade Hub

### Minor Version Upgrade

```bash
# Edit config.yaml - change kubernetes_version
# Then plan and apply
./bootstrap/terragrunt-wrapper.sh staging plan
./bootstrap/terragrunt-wrapper.sh staging apply
```

### Major Component Upgrade

```bash
# Update versions in config.yaml
# Review plan carefully
./bootstrap/terragrunt-wrapper.sh staging plan

# Apply in maintenance window
./bootstrap/terragrunt-wrapper.sh staging apply
```

## Cleanup

### Destroy Infrastructure

⚠️ **Warning**: This will delete ALL resources including EKS cluster and data

```bash
# Destroy infrastructure
./bootstrap/terragrunt-wrapper.sh staging destroy

# Confirm when prompted
```

## Next Steps

- [Deploy Spoke Clusters](spokes.md)
- [Configure Applications](../applications.md)
- [Set up CI/CD](../cicd.md)
- [Configure Monitoring](../monitoring.md)

## Support

For issues or questions:
- Check [Troubleshooting Guide](../troubleshooting.md)
- Open an issue on GitHub
- Consult [Architecture Documentation](../architecture.md)
