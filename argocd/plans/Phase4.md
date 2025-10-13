# Phase 4: Spoke Infrastructure

**Dependencies**: Phase 3 complete (all RGDs deployed)

---

## Overview

Phase 4 provisions the first spoke EKS cluster using KRO-managed infrastructure. This involves creating real AWS resources (VPC, EKS cluster, IAM roles) in the spoke AWS account and registering the spoke cluster with the hub's ArgoCD.

**CRITICAL**: This phase creates billable AWS resources. Ensure budget approvals and cost monitoring are in place.

---

## Objectives

1. ✅ Sync graph-instances ApplicationSet (Wave 2)
2. ✅ Provision spoke1 EKS cluster via KRO
3. ✅ Monitor infrastructure creation (VPC, subnets, NAT gateways, EKS)
4. ✅ Register spoke cluster with hub ArgoCD
5. ✅ Deploy Wave 0 addons to spoke cluster
6. ✅ Validate spoke cluster accessibility and health

---

## Prerequisites

- Phase 3 completed (all RGDs deployed)
- Spoke AWS account configured
- Cross-account IAM roles configured
- Spoke account ID documented
- Budget approval for spoke infrastructure

---

---

## Task Breakdown

### Task 4.1: Pre-Provisioning Validation (1-2 hours)

**Objective**: Verify all prerequisites before creating infrastructure

#### Step 4.1.1: Verify Cross-Account IAM Roles

```bash
# Switch to spoke AWS account
export AWS_PROFILE=spoke1

# Verify assume role from hub works
aws sts assume-role \
  --role-arn arn:aws:iam::<spoke-account-id>:role/KRO-CrossAccountRole \
  --role-session-name test

# Should return credentials successfully

# Switch back to hub account
export AWS_PROFILE=hub
```

#### Step 4.1.2: Verify Spoke Configuration

```bash
# Build spoke1 kustomization
kustomize build argocd/spokes/spoke1/infrastructure/

# Verify output shows:
# - kind: EksCluster
# - metadata.name: spoke1-cluster
# - spec.accountId: <spoke-account-id>
# - spec.vpc.vpcCidr: 10.1.0.0/16
# - All required fields populated

# Validate YAML
kustomize build argocd/spokes/spoke1/infrastructure/ | kubectl apply --dry-run=client -f -
```

#### Step 4.1.3: Verify Graph-Instances ApplicationSet

```bash
# Check ApplicationSet
kubectl get applicationset graph-instances -n argocd

# Verify sync wave
kubectl get applicationset graph-instances -n argocd -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
# Expected: 2

# Check generators (should target hub cluster)
kubectl get applicationset graph-instances -n argocd -o yaml | grep -A 10 "matchLabels"

# Should show: fleet_member: control-plane
```

**Validation Checklist**:
- [ ] Cross-account IAM roles working
- [ ] Spoke1 configuration valid
- [ ] Graph-instances ApplicationSet ready (Wave 2)
- [ ] Hub cluster selected as deployment target

---

### Task 4.2: Provision Spoke Infrastructure (3-5 hours)

**Objective**: Create spoke EKS cluster and supporting infrastructure

#### Step 4.2.1: Sync Graph-Instances ApplicationSet

```bash
# Check if Application already generated
kubectl get applications -n argocd | grep "graph-instances"

# Expected: spoke1-graph-instances

# Sync application
argocd app sync spoke1-graph-instances

# OR if auto-sync disabled
kubectl patch application spoke1-graph-instances -n argocd -p '{"spec":{"syncPolicy":{"automated":{}}}}' --type merge
```

#### Step 4.2.2: Monitor EksCluster Instance Creation

```bash
# Check EksCluster instance created
kubectl get ekscluster -n default

# Expected:
# NAME              AGE
# spoke1-cluster    <age>

# Watch status
watch -n 10 'kubectl get ekscluster spoke1-cluster -o yaml | yq .status'

# Monitor KRO controller logs
kubectl logs -f -n kro-system -l app.kubernetes.io/name=kro | grep spoke1-cluster
```

#### Step 4.2.3: Monitor AWS Resource Creation

**Phase 1: VPC and Networking** (10-15 minutes)
```bash
# Switch to spoke account
export AWS_PROFILE=spoke1

# Watch VPC creation
watch -n 30 'aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spoke1-vpc" --query "Vpcs[0].VpcId"'

# Check subnets
aws ec2 describe-subnets --filters "Name=tag:cluster,Values=spoke1" --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table

# Expected: 6 subnets (3 public + 3 private across 3 AZs)

# Check NAT gateways
aws ec2 describe-nat-gateways --filter "Name=tag:cluster,Values=spoke1"

# Expected: 3 NAT gateways (one per public subnet)

# Check route tables
aws ec2 describe-route-tables --filters "Name=tag:cluster,Values=spoke1"

# Expected: Multiple route tables for public/private routing
```

**Phase 2: IAM Roles** (5 minutes)
```bash
# Check cluster IAM role
aws iam get-role --role-name spoke1-cluster-role

# Check node IAM role
aws iam get-role --role-name spoke1-node-role

# Check service account roles (for ACK controllers, etc.)
aws iam list-roles | jq -r '.Roles[] | select(.RoleName | contains("spoke1-ack-")) | .RoleName'
```

**Phase 3: EKS Cluster** (15-20 minutes)
```bash
# Watch EKS cluster creation
watch -n 60 'aws eks describe-cluster --name spoke1 --query "cluster.status"'

# Status progression:
# CREATING -> ACTIVE (takes 15-20 minutes)

# Get cluster endpoint when active
aws eks describe-cluster --name spoke1 --query "cluster.endpoint" --output text

# Get cluster version
aws eks describe-cluster --name spoke1 --query "cluster.version" --output text
# Expected: 1.32
```

**Phase 4: Node Groups** (10-15 minutes)
```bash
# List node groups
aws eks list-nodegroups --cluster-name spoke1

# Watch node group creation
watch -n 60 'aws eks describe-nodegroup --cluster-name spoke1 --nodegroup-name system --query "nodegroup.status"'

# Status: CREATING -> ACTIVE

# Check node group details
aws eks describe-nodegroup --cluster-name spoke1 --nodegroup-name system

# Verify node count, instance types
```

#### Step 4.2.4: Total Provisioning Time

**Expected Timeline**:
- VPC & Networking: 10-15 minutes
- IAM Roles: 2-5 minutes (parallel with VPC)
- EKS Control Plane: 15-20 minutes
- Node Groups: 10-15 minutes
- **Total**: 35-50 minutes

**Monitoring Dashboard**:
```bash
# Create monitoring script
cat > /tmp/monitor-spoke1.sh <<'EOF'
#!/bin/bash
while true; do
  clear
  echo "=== Spoke1 Provisioning Status ==="
  echo "$(date)"
  echo ""

  echo "Kubernetes Status:"
  kubectl get ekscluster spoke1-cluster -o jsonpath='{.status.phase}' 2>/dev/null || echo "Not created yet"
  echo ""

  echo "AWS VPC:"
  AWS_PROFILE=spoke1 aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spoke1-vpc" --query 'Vpcs[0].State' --output text 2>/dev/null || echo "Not created yet"

  echo "AWS EKS:"
  AWS_PROFILE=spoke1 aws eks describe-cluster --name spoke1 --query 'cluster.status' --output text 2>/dev/null || echo "Not created yet"

  echo "AWS Nodes:"
  AWS_PROFILE=spoke1 aws eks describe-nodegroup --cluster-name spoke1 --nodegroup-name system --query 'nodegroup.status' --output text 2>/dev/null || echo "Not created yet"

  sleep 30
done
EOF
chmod +x /tmp/monitor-spoke1.sh

# Run monitoring
/tmp/monitor-spoke1.sh
```

**Validation Checklist**:
- [ ] EksCluster instance created in hub cluster
- [ ] VPC created in spoke account (10.1.0.0/16)
- [ ] Subnets created (6 total)
- [ ] NAT gateways created (3 total)
- [ ] IAM roles created
- [ ] EKS cluster ACTIVE
- [ ] Node groups ACTIVE
- [ ] Nodes joined cluster

---

### Task 4.3: Register Spoke with Hub ArgoCD (1 hour)

**Objective**: Add spoke cluster to hub ArgoCD for app deployment

#### Step 4.3.1: Get Spoke Kubeconfig

```bash
# Update kubeconfig for spoke1
AWS_PROFILE=spoke1 aws eks update-kubeconfig \
  --name spoke1 \
  --region us-west-2 \
  --alias spoke1

# Test access
kubectl --context spoke1 cluster-info

# Check nodes
kubectl --context spoke1 get nodes

# Expected: 3-5 nodes in Ready state
```

#### Step 4.3.2: Register Spoke with ArgoCD

```bash
# Switch to hub context
kubectl config use-context hub-staging

# Add spoke1 to ArgoCD
argocd cluster add spoke1 \
  --name spoke1 \
  --label fleet_member=spoke \
  --annotation aws_account=<spoke-account-id> \
  --annotation aws_region=us-west-2 \
  --yes

# Verify cluster added
argocd cluster list | grep spoke1

# Check cluster secret in hub
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster,fleet_member=spoke
```

#### Step 4.3.3: Store Credentials in Secrets Manager

```bash
# Get spoke cluster credentials
SPOKE_SERVER=$(kubectl --context spoke1 config view --minify -o jsonpath='{.clusters[0].cluster.server}')
SPOKE_CA=$(kubectl --context spoke1 config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
SPOKE_TOKEN=$(kubectl --context spoke1 create token argocd-manager -n kube-system --duration=876000h)

# Store in AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id staging/spoke1/argocd-secret \
  --secret-string "{
    \"server\": \"$SPOKE_SERVER\",
    \"certificateAuthorityData\": \"$SPOKE_CA\",
    \"token\": \"$SPOKE_TOKEN\"
  }" \
  --region us-west-2
```

**Validation Checklist**:
- [ ] Spoke kubeconfig configured
- [ ] Spoke nodes all Ready
- [ ] Spoke registered with ArgoCD
- [ ] Cluster secret created in hub
- [ ] Credentials stored in Secrets Manager

---

### Task 4.4: Deploy Addons to Spoke (1-2 hours)

**Objective**: Deploy Wave 0 addons to spoke cluster

#### Step 4.4.1: Verify Spoke Addons Configuration

```bash
# Check spoke1 enablement
cat argocd/spokes/spoke1/addons/enablement.yaml

# Should have KRO disabled, ACK controllers enabled
# kro:
#   enabled: false  # KRO only runs on hub
# ec2:
#   enabled: true
# ...

# Check spoke1 values
cat argocd/spokes/spoke1/addons/values.yaml

# Should have spoke-specific IAM role ARNs
```

#### Step 4.4.2: Wait for Addon Applications to Generate

```bash
# Addons ApplicationSet should auto-discover spoke1
# Check generated applications
kubectl get applications -n argocd | grep "spoke1-"

# Expected applications:
# spoke1-cloudtrail
# spoke1-ec2
# spoke1-efs
# ... (all enabled controllers)

# Count spoke1 apps
kubectl get applications -n argocd -l cluster=spoke1 | wc -l

# Expected: ~15-18 apps
```

#### Step 4.4.3: Sync Spoke Addons

```bash
# Sync all spoke1 addons
argocd app sync -l cluster=spoke1

# Monitor sync
watch -n 5 'argocd app list -l cluster=spoke1'

# Wait for all healthy
argocd app wait -l cluster=spoke1 --health --timeout=600
```

#### Step 4.4.4: Verify Addons Deployed to Spoke

```bash
# Switch to spoke context
kubectl config use-context spoke1

# Check ACK system namespace
kubectl get pods -n ack-system

# Expected: ~15 ACK controller pods Running

# Check external secrets
kubectl get pods -n external-secrets-system

# Check kyverno
kubectl get pods -n kyverno

# Verify all pods Running
kubectl get pods -A | grep -v Running | grep -v Completed
# Should return only header line
```

**Validation Checklist**:
- [ ] Spoke addon applications generated
- [ ] All spoke addons synced
- [ ] ACK controllers Running in spoke
- [ ] External Secrets Running in spoke
- [ ] Kyverno Running in spoke
- [ ] All pods healthy

---

### Task 4.5: Validation and Testing (1-2 hours)

**Objective**: Comprehensive validation of spoke infrastructure

#### Step 4.5.1: Network Connectivity Tests

```bash
# Test DNS resolution
kubectl --context spoke1 run test-dns --rm -it --image=busybox -- nslookup kubernetes.default

# Test internet connectivity (via NAT gateway)
kubectl --context spoke1 run test-internet --rm -it --image=curlimages/curl -- curl -I https://www.google.com

# Test pod-to-pod communication
kubectl --context spoke1 run test-pod1 --image=nginx
kubectl --context spoke1 run test-pod2 --image=busybox -- sleep 3600
kubectl --context spoke1 exec test-pod2 -- wget -O- http://test-pod1
```

#### Step 4.5.2: ACK Controller Tests

```bash
# Test EC2 controller on spoke1
kubectl --context spoke1 apply -f - <<EOF
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: test-spoke-sg
  namespace: default
spec:
  description: "Test SG on spoke1"
  name: test-spoke1-sg
  vpcID: <spoke1-vpc-id>
EOF

# Wait and verify
kubectl --context spoke1 wait --for=condition=ACK.ResourceSynced securitygroup/test-spoke-sg --timeout=120s

# Verify in AWS spoke account
AWS_PROFILE=spoke1 aws ec2 describe-security-groups --filters "Name=group-name,Values=test-spoke1-sg"

# Cleanup
kubectl --context spoke1 delete securitygroup test-spoke-sg
```

#### Step 4.5.3: Hub-to-Spoke Communication

```bash
# From hub, check ArgoCD can reach spoke
kubectl --context hub-staging exec -n argocd deployment/argocd-server -- argocd cluster get spoke1

# Should show cluster info and connection status

# Test deploying app to spoke from hub
cat <<EOF | kubectl --context hub-staging apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-spoke-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://<spoke1-server>
    namespace: default
  syncPolicy:
    automated: {}
    syncOptions:
      - CreateNamespace=true
EOF

# Wait for sync
argocd app wait test-spoke-app

# Verify app running on spoke
kubectl --context spoke1 get pods -n default

# Cleanup
kubectl --context hub-staging delete application test-spoke-app
```

**Validation Checklist**:
- [ ] DNS working in spoke
- [ ] Internet access working (NAT gateway)
- [ ] Pod-to-pod communication working
- [ ] ACK controllers functional on spoke
- [ ] Hub ArgoCD can deploy to spoke
- [ ] Test applications run successfully

---

## Rollback Procedure

### If Phase 4 Fails

**Option 1: Delete EksCluster Instance (KRO will cleanup)**
```bash
kubectl delete ekscluster spoke1-cluster

# Monitor cleanup
kubectl get ekscluster spoke1-cluster -o yaml | yq .status.phase

# KRO should delete AWS resources in reverse order:
# - Node groups
# - EKS cluster
# - NAT gateways
# - Subnets
# - VPC
# - IAM roles

# Verify cleanup in AWS
AWS_PROFILE=spoke1 aws eks list-clusters
# spoke1 should not appear

AWS_PROFILE=spoke1 aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spoke1-vpc"
# Should return empty
```

**Option 2: Manual AWS Cleanup (if KRO fails)**
```bash
# Manually delete EKS cluster
AWS_PROFILE=spoke1 aws eks delete-nodegroup --cluster-name spoke1 --nodegroup-name system
AWS_PROFILE=spoke1 aws eks delete-cluster --name spoke1

# Delete VPC (after cluster deleted)
VPC_ID=$(AWS_PROFILE=spoke1 aws ec2 describe-vpcs --filters "Name=tag:Name,Values=spoke1-vpc" --query 'Vpcs[0].VpcId' --output text)

# Delete NAT gateways
AWS_PROFILE=spoke1 aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" --query 'NatGateways[*].NatGatewayId' --output text | xargs -n1 aws ec2 delete-nat-gateway --nat-gateway-id

# Wait for NAT gateways to delete (5-10 minutes)

# Delete subnets, route tables, internet gateway, VPC
# (Use AWS Console or comprehensive script)
```

---

## Success Criteria

### Go/No-Go for Phase 5

- [ ] Spoke1 EKS cluster ACTIVE
- [ ] All nodes Running and Ready
- [ ] Spoke registered with hub ArgoCD
- [ ] All Wave 0 addons deployed to spoke
- [ ] ACK controllers healthy on spoke
- [ ] Network connectivity verified
- [ ] Hub-to-spoke communication working
- [ ] Cost monitoring enabled
- [ ] No critical errors in logs

---

## Next Steps

Upon completion of Phase 4:
1. **Monitor costs** for 24 hours
2. **Run extended validation** tests
3. **Document spoke cluster** details
4. **Brief team on Phase 5** (Gen3 deployment)
5. Proceed to [Phase 5: Workload Deployment](./Phase5.md)

---

---

**Owner**: BabasanmiAdeyemi  
**Username**: boadeyem  
**Team**: RDS Team
