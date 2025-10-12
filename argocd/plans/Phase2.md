# Phase 2: Platform Addons

**Dependencies**: Phase 1 complete

---

## Overview

Phase 2 deploys all platform addons including KRO controller, ACK controllers, external-secrets, and other infrastructure components. This is Wave 0 of the ApplicationSet hierarchy and is critical for subsequent phases.

---

## Objectives

1. ✅ Sync addons ApplicationSet
2. ✅ Deploy KRO controller to hub cluster
3. ✅ Deploy all 15 ACK controllers to hub cluster
4. ✅ Deploy external-secrets operator
5. ✅ Deploy kyverno and platform tools
6. ✅ Validate all controllers are healthy
7. ✅ Test ACK controller functionality

---

## Prerequisites

- Phase 1 completed and signed off
- All IAM roles exist and are correctly configured
- ArgoCD ApplicationSets created
- Hub cluster healthy

---

## Task Breakdown

### Task 2.1: Pre-Deployment Validation (1 hour)

**Objective**: Verify all prerequisites before syncing addons

#### Step 2.1.1: Verify IAM Roles

```bash
# List all ACK IAM roles for hub
aws iam list-roles | jq -r '.Roles[] | select(.RoleName | startswith("hub-staging-ack-")) | .RoleName' | sort

# Expected: 15 roles
# hub-staging-ack-cloudtrail
# hub-staging-ack-cloudwatchlogs
# hub-staging-ack-ec2
# ... (all 15 controllers)

# Verify trust policy for one role (example: ec2)
aws iam get-role --role-name hub-staging-ack-ec2 | jq '.Role.AssumeRolePolicyDocument'

# Should contain OIDC provider and correct service account
```

#### Step 2.1.2: Verify Configuration Files

```bash
# Check catalog has all addons
cat argocd/hub/addons/catalog.yaml | grep "addon:" | wc -l
# Expected: 21 (15 ACK + 6 platform tools)

# Check enablement
cat argocd/hub/addons/enablement.yaml | grep "enabled: true" | wc -l
# Expected: 21

# Verify values file has all role ARNs
cat argocd/hub/addons/values.yaml | grep "role-arn" | wc -l
# Expected: 15 (one per ACK controller)
```

#### Step 2.1.3: Verify Addons ApplicationSet

```bash
# Check ApplicationSet exists
kubectl get applicationset addons -n argocd

# Check sync wave
kubectl get applicationset addons -n argocd -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/sync-wave}'
# Expected: 0

# Check generator configuration
kubectl get applicationset addons -n argocd -o yaml | grep -A 10 "generators:"

# Should show merge generator with catalog, enablement, and values
```

**Validation Checklist**:
- [ ] All 15 ACK IAM roles exist
- [ ] IAM trust policies configured correctly
- [ ] Catalog file complete
- [ ] Enablement file configured
- [ ] Values file has all role ARNs
- [ ] Addons ApplicationSet exists with Wave 0

---

### Task 2.2: Sync Addons ApplicationSet (30 minutes)

**Objective**: Trigger ArgoCD to generate and sync addon applications

#### Step 2.2.1: Check Generated Applications

```bash
# Before sync, check what apps will be generated
argocd appset get addons

# Should show matrix of:
# - catalog items (21 addons)
# - enablement (hub cluster)
# - values (hub cluster)
# = 21 total applications

# Check if apps already exist (they may auto-sync)
kubectl get applications -n argocd | grep "hub-"

# Expected: No apps yet, or some in Progressing state
```

#### Step 2.2.2: Manual Sync (if not auto-synced)

```bash
# Sync all addons at once
argocd app sync -l app.kubernetes.io/part-of=addons

# OR sync individually starting with KRO (critical dependency)
argocd app sync hub-kro

# Wait for KRO to be healthy before syncing others
argocd app wait hub-kro --health

# Then sync ACK controllers
for controller in cloudtrail cloudwatchlogs ec2 efs eks iam kms opensearchservice rds route53 s3 secretsmanager sns sqs wafv2; do
  echo "Syncing hub-$controller..."
  argocd app sync hub-$controller
done

# Finally sync platform tools
argocd app sync hub-external-secrets
argocd app sync hub-kube-state-metrics
argocd app sync hub-kyverno
argocd app sync hub-kyverno-policies
argocd app sync hub-metrics-server
```

#### Step 2.2.3: Monitor Sync Progress

```bash
# Watch all addon apps
watch -n 5 'kubectl get applications -n argocd | grep "hub-"'

# Check sync status
argocd app list -l app.kubernetes.io/part-of=addons

# Monitor ApplicationSet controller logs
kubectl logs -f -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

**Expected Timeline**:
- KRO sync: 2-3 minutes
- Each ACK controller sync: 1-2 minutes
- Platform tools sync: 2-3 minutes each
- **Total**: 20-30 minutes for all addons

---

### Task 2.3: Validate KRO Controller (30 minutes)

**Objective**: Ensure KRO controller is fully operational

#### Step 2.3.1: Check KRO Deployment

```bash
# Check namespace
kubectl get namespace kro-system

# Check pods
kubectl get pods -n kro-system

# Expected pods:
# NAME                                   READY   STATUS    RESTARTS   AGE
# kro-controller-manager-xxx-yyy         2/2     Running   0          5m

# Check pod logs
kubectl logs -n kro-system -l app.kubernetes.io/name=kro --tail=100

# Should show:
# - Controller started
# - Watching ResourceGraphDefinitions
# - No errors
```

#### Step 2.3.2: Verify KRO CRDs

```bash
# List KRO CRDs
kubectl get crd | grep kro.run

# Expected:
# resourcegraphdefinitions.kro.run

# Check CRD details
kubectl get crd resourcegraphdefinitions.kro.run -o yaml

# Verify status
kubectl get crd resourcegraphdefinitions.kro.run -o jsonpath='{.status.conditions[?(@.type=="Established")].status}'
# Expected: True
```

#### Step 2.3.3: Test KRO with Dummy RGD

Create a test RGD to verify KRO is working:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: test-configmap
spec:
  schema:
    apiVersion: v1alpha1
    kind: TestConfigMap
    spec:
      name: string
  resources:
    - id: configmap
      template:
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: {{ .spec.name }}
        data:
          test: "value"
EOF

# Verify RGD created
kubectl get rgd test-configmap

# Create instance
cat <<EOF | kubectl apply -f -
apiVersion: v1alpha1
kind: TestConfigMap
metadata:
  name: test-instance
spec:
  name: my-test-configmap
EOF

# Verify ConfigMap created by KRO
kubectl get configmap my-test-configmap

# Should see ConfigMap with data.test = "value"

# Cleanup
kubectl delete testconfigmap test-instance
kubectl delete rgd test-configmap
```

**Validation Checklist**:
- [ ] KRO pods Running
- [ ] KRO CRD established
- [ ] Test RGD created successfully
- [ ] Test instance creates ConfigMap
- [ ] KRO logs show no errors

---

### Task 2.4: Validate ACK Controllers (2-3 hours)

**Objective**: Verify all 15 ACK controllers are deployed and functional

#### Step 2.4.1: Check ACK Deployments

```bash
# Check namespace
kubectl get namespace ack-system

# Check all ACK pods
kubectl get pods -n ack-system

# Expected: 15 controller pods, all Running
# ack-cloudtrail-controller-xxx
# ack-cloudwatchlogs-controller-xxx
# ack-ec2-controller-xxx
# ... (all 15)

# Check pod status
kubectl get pods -n ack-system -o wide

# Verify all pods are Running with 1/1 Ready
```

#### Step 2.4.2: Verify Service Accounts and IRSA

```bash
# List service accounts
kubectl get sa -n ack-system

# Check one service account for IRSA annotation (example: ec2)
kubectl get sa ack-ec2-controller -n ack-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Expected: arn:aws:iam::123456789012:role/hub-staging-ack-ec2

# Verify all controllers have correct role ARNs
for controller in cloudtrail cloudwatchlogs ec2 efs eks iam kms opensearchservice rds route53 s3 secretsmanager sns sqs wafv2; do
  echo -n "$controller: "
  kubectl get sa ack-$controller-controller -n ack-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
  echo ""
done
```

#### Step 2.4.3: Check ACK Controller Logs

```bash
# Check logs for each controller (sample)
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-ec2-chart --tail=50

# Should show:
# - Controller started
# - Watching AWS resources
# - No permission errors
# - Successfully assumed IAM role (via IRSA)

# Check for errors across all controllers
kubectl logs -n ack-system --all-containers --tail=100 | grep -i error

# Should return minimal or no errors
```

#### Step 2.4.4: Test ACK Controller Functionality

**Test EC2 Controller** (simple test):
```bash
# Create a test SecurityGroup
cat <<EOF | kubectl apply -f -
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: test-sg
  namespace: default
spec:
  description: "Test security group for ACK validation"
  name: test-ack-sg
  vpcID: $(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=hub-staging-vpc" --query 'Vpcs[0].VpcId' --output text)
EOF

# Wait for SecurityGroup to be created
kubectl wait --for=condition=ACK.ResourceSynced securitygroup/test-sg --timeout=120s

# Verify in AWS
aws ec2 describe-security-groups --filters "Name=group-name,Values=test-ack-sg"

# Should show the security group exists

# Cleanup
kubectl delete securitygroup test-sg

# Verify deleted in AWS
aws ec2 describe-security-groups --filters "Name=group-name,Values=test-ack-sg"
# Should return empty
```

**Test S3 Controller**:
```bash
# Create a test S3 bucket
cat <<EOF | kubectl apply -f -
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: test-ack-bucket
  namespace: default
spec:
  name: test-ack-validation-$(date +%s)
EOF

# Wait for bucket creation
kubectl wait --for=condition=ACK.ResourceSynced bucket/test-ack-bucket --timeout=120s

# Verify in AWS
aws s3 ls | grep test-ack-validation

# Cleanup
kubectl delete bucket test-ack-bucket
```

**Validation Checklist**:
- [ ] All 15 ACK controller pods Running
- [ ] All service accounts have IRSA annotations
- [ ] Controller logs show successful IAM role assumption
- [ ] Test resources created successfully via ACK
- [ ] Test resources visible in AWS Console
- [ ] Test resources deleted successfully

---

### Task 2.5: Validate Platform Tools (1-2 hours)

**Objective**: Verify external-secrets, kyverno, and other tools are working

#### Step 2.5.1: Validate External Secrets

```bash
# Check pods
kubectl get pods -n external-secrets-system

# Expected:
# external-secrets-controller-xxx   1/1   Running
# external-secrets-webhook-xxx      1/1   Running

# Create SecretStore (AWS Secrets Manager)
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

# Create ExternalSecret
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-secret
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: test-k8s-secret
  data:
    - secretKey: password
      remoteRef:
        key: staging/hub/argocd-secret
        property: password
EOF

# Verify Secret created
kubectl get secret test-k8s-secret -n default

# Check Secret data
kubectl get secret test-k8s-secret -n default -o jsonpath='{.data.password}' | base64 -d

# Cleanup
kubectl delete externalsecret test-secret
kubectl delete secretstore aws-secrets
kubectl delete secret test-k8s-secret
```

#### Step 2.5.2: Validate Kyverno

```bash
# Check pods
kubectl get pods -n kyverno

# Expected:
# kyverno-admission-controller-xxx   1/1   Running
# kyverno-background-controller-xxx  1/1   Running
# kyverno-cleanup-controller-xxx     1/1   Running

# List installed policies
kubectl get clusterpolicy

# Expected: Several default policies installed

# Test policy (e.g., require labels)
cat <<EOF | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-for-labels
    match:
      any:
      - resources:
          kinds:
          - Pod
    validate:
      message: "Labels 'app' and 'env' are required."
      pattern:
        metadata:
          labels:
            app: "?*"
            env: "?*"
EOF

# Try creating Pod without labels (should fail)
kubectl run test-pod --image=nginx
# Expected error: admission webhook denied the request

# Create Pod with labels (should succeed)
kubectl run test-pod --image=nginx --labels="app=test,env=dev"

# Cleanup
kubectl delete clusterpolicy require-labels
kubectl delete pod test-pod
```

#### Step 2.5.3: Validate Metrics Server

```bash
# Check pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=metrics-server

# Test metrics
kubectl top nodes

# Should show CPU/Memory usage for all nodes

kubectl top pods -n ack-system

# Should show resource usage for ACK controllers
```

**Validation Checklist**:
- [ ] External Secrets pods Running
- [ ] SecretStore and ExternalSecret work
- [ ] Secrets synced from AWS Secrets Manager
- [ ] Kyverno pods Running
- [ ] Kyverno policies installed
- [ ] Policy enforcement working
- [ ] Metrics Server providing data

---

### Task 2.6: Health Monitoring and Alerts (1 hour)

**Objective**: Set up monitoring for addon health

#### Step 2.6.1: Create HealthCheck Script

```bash
cat > /tmp/check-addon-health.sh <<'EOF'
#!/bin/bash
set -e

echo "=== Checking Addon Health ==="

# Check KRO
echo "KRO Controller:"
kubectl get pods -n kro-system -o wide
echo ""

# Check ACK Controllers
echo "ACK Controllers:"
kubectl get pods -n ack-system -o wide | grep -E "Running|NAME"
echo ""

# Count Running ACK controllers
RUNNING=$(kubectl get pods -n ack-system --field-selector=status.phase=Running | grep -c "Running")
echo "ACK Controllers Running: $RUNNING/15"

# Check External Secrets
echo "External Secrets:"
kubectl get pods -n external-secrets-system -o wide
echo ""

# Check Kyverno
echo "Kyverno:"
kubectl get pods -n kyverno -o wide
echo ""

# Check ArgoCD sync status
echo "ArgoCD Addon Sync Status:"
argocd app list -l app.kubernetes.io/part-of=addons --output wide
echo ""

# Summary
echo "=== Summary ==="
HEALTHY=$(argocd app list -l app.kubernetes.io/part-of=addons -o json | jq '[.[] | select(.health.status=="Healthy")] | length')
TOTAL=$(argocd app list -l app.kubernetes.io/part-of=addons -o json | jq 'length')
echo "Healthy Apps: $HEALTHY/$TOTAL"

if [ "$HEALTHY" -eq "$TOTAL" ]; then
  echo "✅ All addons healthy!"
  exit 0
else
  echo "❌ Some addons unhealthy"
  exit 1
fi
EOF

chmod +x /tmp/check-addon-health.sh
```

#### Step 2.6.2: Run Health Checks

```bash
# Run health check
/tmp/check-addon-health.sh

# Schedule periodic checks (optional)
# Add to cron or monitoring system
```

#### Step 2.6.3: Set Up CloudWatch Alarms

```bash
# Create alarm for ACK controller failures
aws cloudwatch put-metric-alarm \
  --alarm-name hub-ack-controllers-down \
  --alarm-description "Alert when ACK controllers are not running" \
  --metric-name PodReady \
  --namespace AWS/ContainerInsights \
  --statistic Average \
  --period 300 \
  --threshold 15 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ClusterName,Value=hub-staging Name=Namespace,Value=ack-system \
  --alarm-actions arn:aws:sns:us-west-2:123456789012:gen3-kro-deployment-alerts
```

**Validation Checklist**:
- [ ] Health check script works
- [ ] All addons report healthy
- [ ] CloudWatch alarms created
- [ ] SNS notifications working

---

## Rollback Procedure

### If Phase 2 Fails

**Option 1: Rollback Specific Addon**
```bash
# Delete problematic Application
argocd app delete hub-<addon-name>

# OR delete via kubectl
kubectl delete application hub-<addon-name> -n argocd

# Fix configuration in git, then re-sync
argocd app sync hub-<addon-name>
```

**Option 2: Rollback All Addons**
```bash
# Delete all addon Applications
argocd app delete -l app.kubernetes.io/part-of=addons

# OR suspend ApplicationSet
kubectl patch applicationset addons -n argocd -p '{"spec":{"generators":[]}}' --type merge

# Fix issues, then re-enable
kubectl patch applicationset addons -n argocd -p '{"spec":{"generators":<original>}}' --type merge
```

**Option 3: Nuclear Option**
```bash
# Delete addons ApplicationSet entirely
kubectl delete applicationset addons -n argocd

# This will cascade delete all addon Applications
# Recreate by re-syncing bootstrap
argocd app sync bootstrap
```

---

## Troubleshooting

### Issue: KRO Controller Not Starting

**Symptoms**: KRO pod in CrashLoopBackOff

**Solutions**:
1. Check logs: `kubectl logs -n kro-system -l app.kubernetes.io/name=kro`
2. Verify CRD installed: `kubectl get crd resourcegraphdefinitions.kro.run`
3. Check RBAC permissions for controller
4. Verify webhook configuration

### Issue: ACK Controller Permission Denied

**Symptoms**: Controller logs show AWS API permission errors

**Solutions**:
1. Verify IAM role ARN in service account annotation
2. Check IAM role trust policy includes OIDC provider
3. Verify AWS managed policy attached to role
4. Test IAM role assumption:
   ```bash
   kubectl run aws-cli --rm -it --image amazon/aws-cli --serviceaccount=ack-ec2-controller --namespace=ack-system -- sts get-caller-identity
   ```

### Issue: External Secrets Not Syncing

**Symptoms**: ExternalSecret shows error status

**Solutions**:
1. Check SecretStore status: `kubectl describe secretstore <name>`
2. Verify IAM permissions for Secrets Manager
3. Check secret exists in AWS: `aws secretsmanager describe-secret --secret-id <name>`
4. Review external-secrets controller logs

### Issue: Kyverno Blocking Legitimate Resources

**Symptoms**: Pod creation fails with policy violation

**Solutions**:
1. Review policy: `kubectl get clusterpolicy <name> -o yaml`
2. Update policy or add exception
3. Temporarily disable policy: `kubectl patch clusterpolicy <name> -p '{"spec":{"validationFailureAction":"Audit"}}'`
4. Delete policy if not needed: `kubectl delete clusterpolicy <name>`

---

## Success Criteria

### Go/No-Go for Phase 3

- [ ] KRO controller Running and healthy
- [ ] All 15 ACK controllers Running and healthy
- [ ] External Secrets operational
- [ ] Kyverno operational
- [ ] All platform tools deployed
- [ ] Test ACK resources created successfully
- [ ] All addon Applications synced and healthy in ArgoCD
- [ ] No critical errors in controller logs
- [ ] Health checks passing

### Metrics

- **Addon Deployment Time**: 20-30 minutes
- **KRO Validation Time**: 5-10 minutes
- **ACK Validation Time**: 1-2 hours
- **Platform Tools Validation**: 1 hour
- **Overall Phase 2 Time**: 4-5 hours (excluding testing)

---

## Documentation

### Outputs to Document

```bash
# Controller versions
kubectl get applications -n argocd | grep "hub-" | awk '{print $1}' > outputs/phase2-deployed-addons.txt

# ACK resources created
kubectl api-resources | grep .services.k8s.aws > outputs/phase2-ack-resources.txt

# Metrics snapshot
kubectl top nodes > outputs/phase2-metrics.txt
kubectl top pods -n ack-system >> outputs/phase2-metrics.txt
```

---

## Next Steps

Upon completion of Phase 2:
1. **Review Phase 2 completion** with team
2. **Run comprehensive health checks** one more time
3. **Verify KRO is ready** for RGD deployment
4. **Update Phase 3 plan** if needed
5. Proceed to [Phase 3: Resource Graphs](./Phase3.md)

---

---

**Owner**: BabasanmiAdeyemi  
**Username**: boadeyem  
**Team**: RDS Team


---

