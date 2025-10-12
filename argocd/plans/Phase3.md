# Phase 3: Resource Graphs

**Dependencies**: Phase 2 complete (KRO controller operational)

---

## Overview

Phase 3 deploys ResourceGraphDefinitions (RGDs) to the hub cluster. These are CRD-based templates that define infrastructure patterns for EKS clusters, VPCs, IAM roles, and other AWS resources managed by KRO.

---

## Objectives

1. ✅ Sync graphs ApplicationSet (Wave 1)
2. ✅ Deploy all RGDs from `shared/graphs/aws/`
3. ✅ Validate RGD CRDs are registered with Kubernetes
4. ✅ Test RGD functionality with sample instances
5. ✅ Prepare for Phase 4 infrastructure provisioning

---

## Prerequisites

- Phase 2 completed and signed off
- KRO controller Running and healthy
- ACK controllers operational
- All Wave 0 addons healthy

---

## Task Breakdown

### Task 3.1: Pre-Deployment Validation (30 minutes)

**Objective**: Verify KRO is ready to accept RGDs

#### Step 3.1.1: Verify KRO Controller Status

```bash
# Check KRO pods
kubectl get pods -n kro-system

# Expected: All pods Running
# NAME                                   READY   STATUS    RESTARTS   AGE
# kro-controller-manager-xxx             2/2     Running   0          <age>

# Check KRO controller logs
kubectl logs -n kro-system -l app.kubernetes.io/name=kro --tail=100

# Should show:
# - Controller running
# - Watching ResourceGraphDefinitions
# - No errors

# Verify KRO CRD exists
kubectl get crd resourcegraphdefinitions.kro.run
```

#### Step 3.1.2: Verify Graphs ApplicationSet

```bash
# Check ApplicationSet exists
kubectl get applicationset graphs -n argocd

# Verify sync wave
kubectl get applicationset graphs -n argocd -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
# Expected: 1

# Check generator configuration
kubectl get applicationset graphs -n argocd -o yaml | grep -A 20 "generators:"

# Should show:
# - clusters generator (fleet_member: control-plane)
# - git files generator (argocd/shared/graphs/**/*.yaml)
```

#### Step 3.1.3: Verify RGD Files Exist

```bash
# List all RGD files in repository
git ls-tree -r staging --name-only argocd/shared/graphs/

# Expected files:
# argocd/shared/graphs/aws/efs-rgd.yaml
# argocd/shared/graphs/aws/eks-basic-rgd.yaml
# argocd/shared/graphs/aws/eks-cluster-rgd.yaml
# argocd/shared/graphs/aws/iam-addons-rgd.yaml
# argocd/shared/graphs/aws/iam-roles-rgd.yaml
# argocd/shared/graphs/aws/vpc-network-rgd.yaml

# Count RGD files
ls argocd/shared/graphs/aws/*.yaml | wc -l
# Expected: 6
```

**Validation Checklist**:
- [ ] KRO controller healthy
- [ ] KRO CRD established
- [ ] Graphs ApplicationSet exists with Wave 1
- [ ] 6 RGD files present in repository

---

### Task 3.2: Sync Graphs ApplicationSet (1 hour)

**Objective**: Deploy all RGDs to hub cluster

#### Step 3.2.1: Check Generated Applications

```bash
# Preview what apps will be created
argocd appset get graphs

# Should show 6 applications (one per RGD file):
# - efs-rgd-hub-staging
# - eks-basic-rgd-hub-staging
# - eks-cluster-rgd-hub-staging
# - iam-addons-rgd-hub-staging
# - iam-roles-rgd-hub-staging
# - vpc-network-rgd-hub-staging

# Check if apps already exist
kubectl get applications -n argocd | grep "rgd"
```

#### Step 3.2.2: Sync Graph Applications

```bash
# Sync all graphs applications
argocd app sync -l app.kubernetes.io/part-of=graphs

# OR sync individually
argocd app sync efs-rgd-hub-staging
argocd app sync eks-basic-rgd-hub-staging
argocd app sync eks-cluster-rgd-hub-staging
argocd app sync iam-addons-rgd-hub-staging
argocd app sync iam-roles-rgd-hub-staging
argocd app sync vpc-network-rgd-hub-staging

# Wait for all to sync
argocd app wait -l app.kubernetes.io/part-of=graphs --health
```

#### Step 3.2.3: Monitor Deployment

```bash
# Watch applications
watch -n 5 'argocd app list -l app.kubernetes.io/part-of=graphs'

# Check sync progress
kubectl get applications -n argocd | grep rgd

# All should show:
# HEALTH: Healthy
# SYNC: Synced
```

**Expected Timeline**:
- RGD deployments are fast (declarative CRDs)
- Each RGD: < 1 minute
- **Total**: 3-5 minutes for all 6 RGDs

---

### Task 3.3: Validate RGD Deployment (1 hour)

**Objective**: Verify all RGDs are registered and functional

#### Step 3.3.1: Check RGD Resources

```bash
# List all RGDs
kubectl get rgd

# Expected:
# NAME                   AGE
# ekscluster.kro.run     <age>
# eks-basic.kro.run      <age>
# efs.kro.run            <age>
# iam-addon-roles.kro.run <age>
# iam-roles.kro.run      <age>
# vpc.kro.run            <age>

# Count RGDs
kubectl get rgd | grep -c "kro.run"
# Expected: 6
```

#### Step 3.3.2: Inspect Individual RGDs

```bash
# Check EKS Cluster RGD
kubectl get rgd ekscluster.kro.run -o yaml

# Verify:
# - spec.schema defined
# - spec.resources defined
# - status.conditions show Ready

# Check status for all RGDs
for rgd in $(kubectl get rgd -o name); do
  echo "=== $rgd ==="
  kubectl get $rgd -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
  echo ""
done

# All should return: True
```

#### Step 3.3.3: Verify Custom Resource Kinds

```bash
# List new CRDs created by RGDs
kubectl get crd | grep -E "ekscluster|eks-basic|efs|iam-addon-roles|iam-roles|vpc"

# These are NOT CRDs themselves, but RGDs define schemas
# Instances will be regular Kubernetes resources with custom kinds

# Check API resources available
kubectl api-resources | grep v1alpha1

# Should show custom kinds like:
# EksCluster, EksBasic, Efs, IamAddonRoles, IamRoles, Vpc
```

#### Step 3.3.4: Review RGD Specifications

For each RGD, verify it matches expected schema:

**EKS Cluster RGD** (`argocd/shared/graphs/aws/eks-cluster-rgd.yaml`):
```bash
kubectl get rgd ekscluster.kro.run -o jsonpath='{.spec.schema.spec}' | jq .

# Should show schema with fields:
# - name, tenant, environment, region
# - k8sVersion, accountId, managementAccountId
# - vpc (create, vpcCidr, subnets)
# - gitops (enabled, repoUrl, repoPath, repoRevision)
# - workloads
```

**VPC RGD** (`argocd/shared/graphs/aws/vpc-network-rgd.yaml`):
```bash
kubectl get rgd vpc.kro.run -o jsonpath='{.spec.schema.spec}' | jq .

# Should show schema for VPC creation with:
# - vpcCidr
# - publicSubnets, privateSubnets
# - enableDnsHostnames, enableDnsSupport
```

**Validation Checklist**:
- [ ] All 6 RGDs deployed
- [ ] All RGDs show Ready status
- [ ] RGD specifications correct
- [ ] No errors in KRO controller logs

---

### Task 3.4: Test RGD Functionality (2-3 hours)

**Objective**: Create test instances to validate RGDs work correctly

#### Step 3.4.1: Test VPC RGD (Simplest)

```bash
# Create a test VPC instance
cat <<EOF | kubectl apply -f -
apiVersion: v1alpha1
kind: Vpc
metadata:
  name: test-vpc
  namespace: default
spec:
  vpcCidr: "10.99.0.0/16"
  publicSubnets:
    - cidr: "10.99.1.0/24"
      availabilityZone: "us-west-2a"
    - cidr: "10.99.2.0/24"
      availabilityZone: "us-west-2b"
  privateSubnets:
    - cidr: "10.99.11.0/24"
      availabilityZone: "us-west-2a"
    - cidr: "10.99.12.0/24"
      availabilityZone: "us-west-2b"
  enableDnsHostnames: true
  enableDnsSupport: true
  tags:
    Name: "test-vpc"
    Environment: "test"
EOF

# Wait for VPC to be created
kubectl wait --for=condition=Ready vpc/test-vpc --timeout=300s

# Check status
kubectl get vpc test-vpc -o yaml

# Should show:
# - status.vpcId (AWS VPC ID)
# - status.conditions Ready=True

# Verify VPC exists in AWS
VPC_ID=$(kubectl get vpc test-vpc -o jsonpath='{.status.vpcId}')
aws ec2 describe-vpcs --vpc-ids $VPC_ID

# Should show VPC with CIDR 10.99.0.0/16

# Check subnets created
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"

# Should show 4 subnets (2 public + 2 private)

# Cleanup
kubectl delete vpc test-vpc

# Verify VPC deleted in AWS
aws ec2 describe-vpcs --vpc-ids $VPC_ID
# Should return error: VPC not found
```

#### Step 3.4.2: Test IAM Roles RGD

```bash
# Create a test IAM role instance
cat <<EOF | kubectl apply -f -
apiVersion: v1alpha1
kind: IamRoles
metadata:
  name: test-iam-role
  namespace: default
spec:
  roleName: "kro-test-role"
  description: "Test IAM role created by KRO"
  assumeRolePolicyDocument: |
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
  managedPolicyArns:
    - "arn:aws:iam::aws:policy/ReadOnlyAccess"
  tags:
    Name: "kro-test-role"
EOF

# Wait for role creation
kubectl wait --for=condition=Ready iamroles/test-iam-role --timeout=300s

# Check status
kubectl get iamroles test-iam-role -o yaml

# Verify role exists in AWS
ROLE_NAME=$(kubectl get iamroles test-iam-role -o jsonpath='{.status.roleName}')
aws iam get-role --role-name $ROLE_NAME

# Should show role with attached ReadOnlyAccess policy

# Cleanup
kubectl delete iamroles test-iam-role

# Verify role deleted
aws iam get-role --role-name $ROLE_NAME
# Should return error: Role not found
```

#### Step 3.4.3: Test EFS RGD

```bash
# NOTE: EFS requires a VPC, so create VPC first (or use existing hub VPC)
HUB_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=hub-staging-vpc" --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$HUB_VPC_ID" --query 'Subnets[0].SubnetId' --output text)

# Create test EFS instance
cat <<EOF | kubectl apply -f -
apiVersion: v1alpha1
kind: Efs
metadata:
  name: test-efs
  namespace: default
spec:
  name: "kro-test-efs"
  encrypted: true
  performanceMode: "generalPurpose"
  throughputMode: "bursting"
  subnetId: "$SUBNET_ID"
  tags:
    Name: "kro-test-efs"
EOF

# Wait for EFS creation
kubectl wait --for=condition=Ready efs/test-efs --timeout=600s

# Check status
kubectl get efs test-efs -o yaml

# Verify EFS in AWS
EFS_ID=$(kubectl get efs test-efs -o jsonpath='{.status.fileSystemId}')
aws efs describe-file-systems --file-system-id $EFS_ID

# Should show EFS with encrypted=true

# Cleanup
kubectl delete efs test-efs

# Verify EFS deleted
aws efs describe-file-systems --file-system-id $EFS_ID
# Should return error: File system not found
```

**Validation Checklist**:
- [ ] VPC RGD creates VPC and subnets successfully
- [ ] IAM Roles RGD creates role with policies
- [ ] EFS RGD creates encrypted file system
- [ ] All resources visible in AWS Console
- [ ] All resources cleaned up after deletion
- [ ] KRO controller logs show successful reconciliation

---

### Task 3.5: Prepare for Phase 4 (1 hour)

**Objective**: Verify readiness for spoke infrastructure provisioning

#### Step 3.5.1: Review EKS Cluster RGD

```bash
# Inspect EKS Cluster RGD (most complex)
kubectl get rgd ekscluster.kro.run -o yaml > /tmp/eks-cluster-rgd.yaml

# Review schema
cat /tmp/eks-cluster-rgd.yaml | yq '.spec.schema'

# Verify all required fields are defined:
# - name, tenant, environment, region
# - k8sVersion, accountId, managementAccountId
# - adminRoleName
# - fleetSecretManagerSecretNameSuffix
# - domainName
# - vpc (all subnet CIDRs)
# - workloads
# - gitops
```

#### Step 3.5.2: Validate Shared Instance Template

```bash
# Review shared EKS cluster instance template
cat argocd/shared/instances/eks-cluster-instance.yaml

# Verify it uses EksCluster kind:
# apiVersion: v1alpha1
# kind: EksCluster

# Check all required fields are present
kustomize build argocd/shared/instances/

# Should build without errors
```

#### Step 3.5.3: Validate Spoke1 Kustomization

```bash
# Build spoke1 infrastructure kustomization
kustomize build argocd/spokes/spoke1/infrastructure/

# Should output complete EksCluster manifest with:
# - name: spoke1-cluster
# - accountId: <spoke1-account-id>
# - vpc.vpcCidr: 10.1.0.0/16
# - All spoke1-specific values applied

# Validate YAML
kustomize build argocd/spokes/spoke1/infrastructure/ | kubectl apply --dry-run=client -f -

# Should validate successfully
```

#### Step 3.5.4: Document RGD Status

```bash
# Export RGD list
kubectl get rgd -o yaml > outputs/phase3-rgds.yaml

# Create summary
cat > outputs/phase3-summary.txt <<EOF
Phase 3: Resource Graphs - Completion Summary

RGDs Deployed:
$(kubectl get rgd -o name)

RGD Status:
$(kubectl get rgd -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[0].status)

Applications Deployed:
$(argocd app list -l app.kubernetes.io/part-of=graphs -o name)

ArgoCD Sync Status:
$(argocd app list -l app.kubernetes.io/part-of=graphs)

Test Results:
- VPC RGD: ✅ Passed
- IAM Roles RGD: ✅ Passed
- EFS RGD: ✅ Passed

Ready for Phase 4: YES
EOF

cat outputs/phase3-summary.txt
```

**Validation Checklist**:
- [ ] EKS Cluster RGD schema reviewed
- [ ] Shared instance template valid
- [ ] Spoke1 kustomization builds correctly
- [ ] All RGDs documented

---

## Rollback Procedure

### If Phase 3 Fails

**Option 1: Rollback Specific RGD**
```bash
# Delete problematic RGD Application
argocd app delete <rgd-name>-hub-staging

# OR via kubectl
kubectl delete application <rgd-name>-hub-staging -n argocd

# Fix RGD file in git
git commit -m "Fix RGD"
git push

# Re-sync
argocd app sync <rgd-name>-hub-staging
```

**Option 2: Rollback All RGDs**
```bash
# Delete all graph Applications
argocd app delete -l app.kubernetes.io/part-of=graphs

# OR delete RGD resources directly
kubectl delete rgd --all

# Fix issues, then re-sync graphs ApplicationSet
argocd app sync -l app.kubernetes.io/part-of=graphs
```

**Option 3: Delete Graphs ApplicationSet**
```bash
# Suspend graphs ApplicationSet
kubectl patch applicationset graphs -n argocd -p '{"spec":{"generators":[]}}' --type merge

# Delete all RGDs
kubectl delete rgd --all

# Fix issues in git
git commit -m "Fix RGDs"
git push

# Re-enable ApplicationSet
kubectl patch applicationset graphs -n argocd -p '{"spec":{"generators":<original>}}' --type merge

# OR re-sync bootstrap
argocd app sync bootstrap
```

---

## Troubleshooting

### Issue: RGD Not Creating Resources

**Symptoms**: Instance created but no AWS resources

**Solutions**:
1. Check KRO controller logs:
   ```bash
   kubectl logs -n kro-system -l app.kubernetes.io/name=kro --tail=200
   ```
2. Check instance status:
   ```bash
   kubectl get <kind> <name> -o yaml | yq '.status'
   ```
3. Verify ACK controllers are running:
   ```bash
   kubectl get pods -n ack-system
   ```
4. Check ACK controller permissions (IRSA)

### Issue: RGD Shows Not Ready

**Symptoms**: `kubectl get rgd` shows Ready=False

**Solutions**:
1. Describe RGD:
   ```bash
   kubectl describe rgd <name>
   ```
2. Check for schema validation errors
3. Verify KRO version compatibility
4. Review RGD YAML for syntax errors

### Issue: Instance Deletion Hangs

**Symptoms**: `kubectl delete` hangs waiting for finalizers

**Solutions**:
1. Check KRO controller is running
2. Manually delete AWS resources:
   ```bash
   # For VPC
   aws ec2 delete-vpc --vpc-id <vpc-id>

   # For IAM role
   aws iam delete-role --role-name <role-name>
   ```
3. Remove finalizers (last resort):
   ```bash
   kubectl patch <kind> <name> -p '{"metadata":{"finalizers":[]}}' --type merge
   ```

### Issue: ArgoCD App OutOfSync

**Symptoms**: Graph Application shows OutOfSync

**Solutions**:
1. Check diff in ArgoCD UI
2. Sync application:
   ```bash
   argocd app sync <app-name>
   ```
3. If RGD is immutable, may need to delete and recreate
4. Check for manual changes to RGD:
   ```bash
   kubectl diff -f argocd/shared/graphs/aws/<file>.yaml
   ```

---

## Success Criteria

### Go/No-Go for Phase 4

- [ ] All 6 RGDs deployed and Ready
- [ ] All graph Applications synced and healthy
- [ ] VPC RGD test passed
- [ ] IAM Roles RGD test passed
- [ ] EFS RGD test passed
- [ ] EKS Cluster RGD schema validated
- [ ] Shared instance template valid
- [ ] Spoke1 kustomization builds successfully
- [ ] No errors in KRO controller logs
- [ ] No errors in ArgoCD logs

### Metrics

- **RGD Deployment Time**: 3-5 minutes (all 6)
- **RGD Validation Time**: 1 hour
- **RGD Testing Time**: 2-3 hours
- **Phase 4 Prep Time**: 1 hour
- **Overall Phase 3 Time**: 4-6 hours

---

## Documentation

### Outputs to Document

```bash
# Save RGD list
kubectl get rgd -o yaml > outputs/phase3-rgds.yaml

# Save ArgoCD apps
argocd app list -l app.kubernetes.io/part-of=graphs -o yaml > outputs/phase3-apps.yaml

# Screenshot ArgoCD UI showing all graph apps
```

---

## Next Steps

Upon completion of Phase 3:
1. **Review Phase 3 completion** with team
2. **Final RGD validation** - all tests passed
3. **Confirm spoke1 configuration** is ready
4. Proceed to [Phase 4: Spoke Infrastructure](./Phase4.md)

**CRITICAL NOTE**: Phase 4 will provision real infrastructure in AWS (EKS cluster, VPC, etc.). Ensure spoke AWS account is ready.

---

**Owner**: BabasanmiAdeyemi
**Username**: boadeyem
**Team**: RDS Team
