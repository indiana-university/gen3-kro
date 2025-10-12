# Phase 1: Hub Bootstrap

**Dependencies**: Phase 0 complete

---

## Overview

Phase 1 deploys the hub EKS cluster with ArgoCD and the bootstrap ApplicationSet. This establishes the control plane that will manage all subsequent deployments.

---

## Objectives

1. ✅ Deploy hub EKS cluster via Terraform
2. ✅ Install ArgoCD in hub cluster
3. ✅ Deploy bootstrap ApplicationSet
4. ✅ Verify ArgoCD can sync from git repository
5. ✅ Validate all 4 child ApplicationSets are created
6. ✅ Configure ArgoCD UI access

---

## Prerequisites

- Phase 0 completed and signed off
- All IAM roles exist
- Terraform state backend configured
- AWS credentials configured
- VPN/bastion access to hub cluster (if private)

---

## Task Breakdown

### Task 1.1: Deploy Hub EKS Cluster (3-4 hours)

**Objective**: Create hub EKS cluster using Terraform

#### Step 1.1.1: Review Terraform Configuration

**File**: `terraform/live/staging/hub-cluster/terragrunt.hcl`

Verify configuration:
```hcl
terraform {
  source = "../../../modules/eks-hub"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

inputs = {
  cluster_name    = "hub-staging"
  cluster_version = "1.32"
  region          = "us-west-2"

  vpc_cidr = "10.0.0.0/16"

  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  node_groups = {
    system = {
      desired_size = 3
      min_size     = 3
      max_size     = 6
      instance_types = ["t3.large"]

      labels = {
        role = "system"
      }

      taints = []
    }

    workload = {
      desired_size = 2
      min_size     = 2
      max_size     = 10
      instance_types = ["t3.xlarge"]

      labels = {
        role = "workload"
      }

      taints = []
    }
  }

  enable_irsa = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Fleet       = "hub"
  }
}
```

#### Step 1.1.2: Plan Deployment

```bash
cd terraform/live/staging/hub-cluster

# Initialize Terraform
terragrunt init

# Plan deployment
terragrunt plan -out=tfplan

# Review plan output
# Expected resources: ~50-60 resources
# - VPC, subnets, route tables, NAT gateways
# - EKS cluster, node groups
# - Security groups
# - IAM roles for nodes
# - OIDC provider
```

**Review Checklist**:
- [ ] VPC CIDR does not conflict with other networks
- [ ] Subnets properly distributed across 3 AZs
- [ ] Node group sizes appropriate for workload
- [ ] IRSA enabled for service accounts
- [ ] Cluster version is 1.32

#### Step 1.1.3: Apply Deployment

```bash
# Apply Terraform plan
terragrunt apply tfplan

# Monitor deployment (20-30 minutes)
# Watch for:
# - VPC creation
# - EKS cluster creation (15-20 min)
# - Node group creation (5-10 min)
```

**Expected Output**:
```
Apply complete! Resources: 56 added, 0 changed, 0 destroyed.

Outputs:
cluster_name = "hub-staging"
cluster_endpoint = "https://XXXXXX.gr7.us-west-2.eks.amazonaws.com"
cluster_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-west-2.amazonaws.com/id/XXXXXX"
cluster_oidc_provider_url = "oidc.eks.us-west-2.amazonaws.com/id/XXXXXX"
cluster_certificate_authority_data = "<base64-encoded-cert>"
```

#### Step 1.1.4: Configure kubectl Access

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name hub-staging \
  --region us-west-2 \
  --alias hub-staging

# Verify access
kubectl cluster-info

# Expected output:
# Kubernetes control plane is running at https://XXXXXX.gr7.us-west-2.eks.amazonaws.com
# CoreDNS is running at https://XXXXXX.gr7.us-west-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

# Check nodes
kubectl get nodes

# Expected: 5 nodes (3 system + 2 workload)
```

**Validation**:
- [ ] EKS cluster created
- [ ] Node groups running
- [ ] kubectl can connect
- [ ] All nodes in Ready state
- [ ] CoreDNS pods running

---

### Task 1.2: Install ArgoCD (1-2 hours)

**Objective**: Deploy ArgoCD to hub cluster using Terraform

#### Step 1.2.1: Review ArgoCD Terraform Module

**File**: `terraform/modules/argocd-bootstrap/main.tf`

Verify ArgoCD configuration includes:
- Namespace creation
- ArgoCD Helm chart deployment
- Initial admin credentials
- Service exposure (LoadBalancer or Ingress)

#### Step 1.2.2: Deploy ArgoCD

```bash
cd terraform/live/staging/argocd-bootstrap

# Initialize
terragrunt init

# Plan
terragrunt plan -out=tfplan

# Apply
terragrunt apply tfplan

# Monitor deployment (5-10 minutes)
```

#### Step 1.2.3: Verify ArgoCD Installation

```bash
# Check ArgoCD namespace
kubectl get namespace argocd

# Check ArgoCD pods
kubectl get pods -n argocd

# Expected pods:
# - argocd-application-controller
# - argocd-applicationset-controller
# - argocd-dex-server
# - argocd-notifications-controller
# - argocd-redis
# - argocd-repo-server
# - argocd-server

# Wait for all pods to be Running
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

#### Step 1.2.4: Access ArgoCD UI

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access UI (if no LoadBalancer)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Or get LoadBalancer URL
kubectl get svc argocd-server -n argocd

# Access UI at https://localhost:8080 or LoadBalancer URL
# Username: admin
# Password: <from secret above>
```

#### Step 1.2.5: Change Admin Password

```bash
# Login via CLI
argocd login localhost:8080 --username admin --password <initial-password> --insecure

# Change password
argocd account update-password

# Update password in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id staging/hub/argocd-secret \
  --secret-string "{\"username\":\"admin\",\"password\":\"<new-password>\"}" \
  --region us-west-2
```

**Validation**:
- [ ] All ArgoCD pods Running
- [ ] ArgoCD UI accessible
- [ ] Admin password changed
- [ ] ArgoCD CLI configured

---

### Task 1.3: Configure Git Repository Access (30 minutes)

**Objective**: Connect ArgoCD to GitHub repository

#### Step 1.3.1: Create Deploy Key (if using SSH)

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "argocd-hub-staging" -f ~/.ssh/argocd-hub-staging -N ""

# Add public key to GitHub repository
# Settings → Deploy keys → Add deploy key
# Paste contents of ~/.ssh/argocd-hub-staging.pub
```

#### Step 1.3.2: Add Repository to ArgoCD

Via UI:
1. Navigate to Settings → Repositories
2. Click "Connect Repo"
3. Select "Via SSH" or "Via HTTPS"
4. Enter repository URL: `git@github.com:indiana-university/gen3-kro.git`
5. Enter private key (if SSH)
6. Click "Connect"

Via CLI:
```bash
argocd repo add git@github.com:indiana-university/gen3-kro.git \
  --ssh-private-key-path ~/.ssh/argocd-hub-staging \
  --name gen3-kro
```

#### Step 1.3.3: Verify Repository Connection

```bash
# List repositories
argocd repo list

# Expected output:
# TYPE  NAME       REPO                                               INSECURE  OCI    LFS    CREDS  STATUS      MESSAGE
# git   gen3-kro   git@github.com:indiana-university/gen3-kro.git     false     false  false  false  Successful
```

**Validation**:
- [ ] Repository added to ArgoCD
- [ ] Connection status: Successful
- [ ] Can browse files in ArgoCD UI

---

### Task 1.4: Deploy Bootstrap ApplicationSet (1 hour)

**Objective**: Deploy bootstrap ApplicationSet that manages all child ApplicationSets

#### Step 1.4.1: Register Hub Cluster with ArgoCD

```bash
# Get cluster context
kubectl config current-context
# hub-staging

# Add cluster to ArgoCD (in-cluster)
argocd cluster add $(kubectl config current-context) \
  --name hub-staging \
  --label fleet_member=control-plane \
  --annotation fleet_repo_url=https://github.com/indiana-university/gen3-kro.git \
  --annotation fleet_repo_basepath=argocd/ \
  --annotation fleet_repo_path=bootstrap \
  --annotation fleet_repo_revision=staging
```

#### Step 1.4.2: Apply Bootstrap ApplicationSet

The bootstrap ApplicationSet is deployed via Terraform in the argocd-bootstrap module.

Verify it exists:
```bash
kubectl get applicationset -n argocd

# Expected:
# NAME        AGE
# bootstrap   <age>

# Check details
kubectl get applicationset bootstrap -n argocd -o yaml
```

#### Step 1.4.3: Verify Bootstrap Sync

```bash
# Check bootstrap Application
kubectl get application -n argocd bootstrap

# Wait for sync
kubectl wait --for=condition=Synced application/bootstrap -n argocd --timeout=300s

# Check sync status
argocd app get bootstrap

# Expected:
# Name:               bootstrap
# Project:            default
# Server:             https://kubernetes.default.svc
# Namespace:          argocd
# URL:                https://<argocd-server>/applications/bootstrap
# Repo:               https://github.com/indiana-university/gen3-kro.git
# Target:             staging
# Path:               argocd/bootstrap
# SyncWindow:         Sync Allowed
# Sync Policy:        Automated
# Sync Status:        Synced to staging (abc123)
# Health Status:      Healthy
```

#### Step 1.4.4: Verify Child ApplicationSets Created

```bash
# List all ApplicationSets
kubectl get applicationsets -n argocd

# Expected:
# NAME               AGE
# bootstrap          10m
# addons             5m
# graphs             5m
# graph-instances    5m
# gen3-instances     5m

# Check each ApplicationSet
for appset in addons graphs graph-instances gen3-instances; do
  echo "=== $appset ==="
  kubectl get applicationset $appset -n argocd -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
  echo ""
done

# Expected sync waves:
# addons: 0
# graphs: 1
# graph-instances: 2
# gen3-instances: 3
```

**Validation**:
- [ ] Bootstrap Application synced
- [ ] 4 child ApplicationSets created
- [ ] Sync waves correct (0, 1, 2, 3)
- [ ] No sync errors in ArgoCD UI

---

### Task 1.5: Validation and Health Checks (30 minutes)

**Objective**: Verify entire Phase 1 deployment is healthy

#### Step 1.5.1: Cluster Health

```bash
# Check cluster health
kubectl get --raw='/readyz?verbose'

# Check node health
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check resource usage
kubectl top nodes
```

#### Step 1.5.2: ArgoCD Health

```bash
# Check ArgoCD components
kubectl get pods -n argocd

# Check ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50

# Should show:
# - ApplicationSets discovered
# - Applications generated
# - No errors
```

#### Step 1.5.3: Bootstrap Health

```bash
# Check bootstrap Application
argocd app get bootstrap

# Check generated Applications (should be 0 at this point, Wave 0 not synced yet)
kubectl get applications -n argocd

# Expected: Only "bootstrap" Application exists
# Child apps will be created when their ApplicationSets generate them
```

#### Step 1.5.4: Metrics and Logging

```bash
# Check ArgoCD metrics endpoint
kubectl port-forward -n argocd svc/argocd-metrics 8082:8082 &
curl http://localhost:8082/metrics | grep argocd_app_info

# Check logs are flowing to CloudWatch (if configured)
aws logs tail /aws/eks/hub-staging/cluster --follow
```

**Validation Checklist**:
- [ ] All cluster nodes healthy
- [ ] All ArgoCD pods Running
- [ ] Bootstrap Application synced
- [ ] 4 child ApplicationSets created
- [ ] ApplicationSet controller logs show no errors
- [ ] ArgoCD UI accessible
- [ ] Metrics endpoint working

---

## Rollback Procedure

### If Phase 1 Fails

**Option 1: Rollback ArgoCD Only**
```bash
cd terraform/live/staging/argocd-bootstrap
terragrunt destroy -auto-approve
```

**Option 2: Rollback Entire Hub Cluster**
```bash
# Destroy ArgoCD first
cd terraform/live/staging/argocd-bootstrap
terragrunt destroy -auto-approve

# Destroy cluster
cd terraform/live/staging/hub-cluster
terragrunt destroy -auto-approve
```

**Option 3: Fix in Place**
```bash
# Delete problematic ApplicationSet
kubectl delete applicationset <name> -n argocd

# Fix configuration in git
git commit -m "Fix ApplicationSet"
git push

# Re-sync bootstrap
argocd app sync bootstrap
```

---

## Troubleshooting

### Issue: EKS Cluster Creation Fails

**Symptoms**: Terraform error during cluster creation

**Solutions**:
1. Check AWS quotas: VPCs, EIPs, NAT Gateways
2. Verify IAM permissions: Ensure user has `eks:CreateCluster`
3. Check VPC CIDR conflicts: Ensure no overlap with existing VPCs
4. Review Terraform logs: `terragrunt apply` output

### Issue: ArgoCD Pods Not Running

**Symptoms**: Pods in CrashLoopBackOff or Pending

**Solutions**:
1. Check node resources: `kubectl describe nodes`
2. Check pod events: `kubectl describe pod <pod-name> -n argocd`
3. Check logs: `kubectl logs <pod-name> -n argocd`
4. Verify EBS CSI driver: `kubectl get csidriver`

### Issue: Bootstrap ApplicationSet Not Creating Apps

**Symptoms**: No child ApplicationSets created

**Solutions**:
1. Check ApplicationSet controller logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
   ```
2. Verify cluster labels:
   ```bash
   kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml
   ```
3. Check git repository access:
   ```bash
   argocd repo get https://github.com/indiana-university/gen3-kro.git
   ```
4. Verify file paths in bootstrap directory:
   ```bash
   git ls-tree -r staging argocd/bootstrap/
   ```

### Issue: ArgoCD UI Not Accessible

**Symptoms**: Cannot connect to ArgoCD UI

**Solutions**:
1. Check service type:
   ```bash
   kubectl get svc argocd-server -n argocd
   ```
2. If LoadBalancer, check AWS:
   ```bash
   aws elbv2 describe-load-balancers
   ```
3. Use port-forward as workaround:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
4. Check security groups for LoadBalancer

---

## Success Criteria

### Go/No-Go for Phase 2

- [ ] Hub EKS cluster fully operational
- [ ] All nodes in Ready state
- [ ] ArgoCD fully deployed and accessible
- [ ] Bootstrap ApplicationSet synced successfully
- [ ] 4 child ApplicationSets created with correct sync waves
- [ ] No errors in ArgoCD ApplicationSet controller logs
- [ ] Git repository connected and accessible
- [ ] ArgoCD metrics endpoint responding
- [ ] All validation checks passing

### Metrics

- **Cluster Deployment Time**: < 30 minutes
- **ArgoCD Deployment Time**: < 10 minutes
- **Bootstrap Sync Time**: < 5 minutes
- **ApplicationSet Creation Time**: < 2 minutes
- **Overall Phase 1 Time**: < 2 hours (excluding planning)

---

## Documentation

### Outputs to Document

Save these values for Phase 2:
```bash
# Cluster info
echo "Cluster Name: hub-staging" >> outputs/phase1-outputs.txt
echo "Cluster Endpoint: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" >> outputs/phase1-outputs.txt
echo "OIDC Provider: $(aws eks describe-cluster --name hub-staging --query 'cluster.identity.oidc.issuer' --output text)" >> outputs/phase1-outputs.txt

# ArgoCD info
echo "ArgoCD URL: $(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')" >> outputs/phase1-outputs.txt
echo "ArgoCD Admin Password: (stored in AWS Secrets Manager)" >> outputs/phase1-outputs.txt

# ApplicationSets
kubectl get applicationsets -n argocd -o yaml > outputs/phase1-applicationsets.yaml
```

### Screenshots to Capture

1. ArgoCD UI showing bootstrap Application
2. ApplicationSets list in ArgoCD UI
3. Cluster nodes in AWS Console
4. kubectl get nodes output

---

## Next Steps

Upon completion of Phase 1:
1. **Review Phase 1 completion** with team
2. **Document any issues** encountered and solutions
3. **Update Phase 2 plan** if needed based on Phase 1 findings
4. **Schedule Phase 2 kickoff** (recommend 1 day buffer)
5. Proceed to [Phase 2: Platform Addons](./Phase2.md)

---

---

**Owner**: BabasanmiAdeyemi  
**Username**: boadeyem  
**Team**: RDS Team


---

