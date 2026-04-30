---
name: kro-status-report
description: 'Report the health status of all KRO instances and ACK resources in a gen3-kro spoke namespace. Use when: user asks for a status report, asks "what is the state of spoke1", asks to check if all resources are Ready, asks to verify a deployment succeeded, or asks to summarise the KRO instance health.'
allowed-tools: Bash
---

# KRO Status Report

Produce a concise health summary of all KRO instances and their dependent ACK resources in a spoke namespace.

## Step 1 — Discover the spoke namespace

```bash
# List all spoke namespaces (named after the spoke, e.g. spoke1)
kubectl get namespaces | grep -v kube- | grep -v argocd | grep -v kro | grep -v ack

# Or list KRO instance CRs across all namespaces
kubectl get resourcegraphdefinitions -A 2>/dev/null || true
```

Ask the user for the namespace if not clear from context.

## Step 2 — List all KRO instances in the namespace

```bash
NAMESPACE="<spoke-namespace>"

# Get all KRO-managed CRs (known kinds)
for kind in AwsGen3Foundation1 AwsGen3Storage1 AwsGen3Database1 AwsGen3Search1 AwsGen3Compute1 AwsGen3IAM1 AwsGen3Messaging1 AwsGen3ClusterResources1 AwsGen3Helm1 AwsGen3Advanced1; do
  kubectl get ${kind,,} -n $NAMESPACE 2>/dev/null && echo "---" || true
done
```

## Step 3 — Check ready conditions for each instance

```bash
kubectl get awsgen3foundation1,awsgen3storage1,awsgen3database1,awsgen3search1,awsgen3compute1,awsgen3iam1,awsgen3messaging1,awsgen3clusterresources1,awsgen3helm1,awsgen3advanced1 \
  -n $NAMESPACE \
  -o custom-columns='KIND:.kind,NAME:.metadata.name,STATE:.status.state,READY:.status.conditions[?(@.type=="Ready")].status' \
  2>/dev/null || echo "Some kinds may not exist in this namespace"
```

## Step 4 — Check bridge ConfigMaps

```bash
kubectl get configmaps -n $NAMESPACE -o custom-columns='NAME:.metadata.name,KEYS:.data' \
  | grep -E 'Bridge|bridge' || echo "No bridge ConfigMaps found"
```

## Step 5 — Check ACK resource health (spot check)

```bash
# Check for any ACK Terminal conditions (permanent errors)
kubectl get -n $NAMESPACE \
  dbinstances.rds.services.k8s.aws,\
replicationgroups.elasticache.services.k8s.aws,\
domains.opensearchservice.services.k8s.aws,\
nodegroups.eks.services.k8s.aws \
  -o wide 2>/dev/null | grep -v "^$" || echo "No ACK resources found in namespace"
```

## Step 6 — Check ArgoCD application sync status

```bash
# If argocd CLI is available
argocd app list --output table 2>/dev/null | grep -i "$NAMESPACE" \
  || kubectl get applications.argoproj.io -n argocd 2>/dev/null | grep "$NAMESPACE"
```

## Output Format

Present a status table:

```
SPOKE NAMESPACE: <name>
Generated: <timestamp>

KRO INSTANCES
─────────────────────────────────────────────────────
KIND                       NAME       STATE    READY
AwsGen3Foundation1         main       Active   True
AwsGen3Storage1            main       Active   True
AwsGen3Database1           main       Pending  False  ← ISSUE
...

BRIDGE CONFIGMAPS
─────────────────────────────────────────────────────
foundationBridge      ✅ present  (vpcId, subnets, ...)
databasePrepBridge    ✅ present
storageBridge         ✅ present
...

ISSUES DETECTED
─────────────────────────────────────────────────────
1. AwsGen3Database1/main: <condition message>
   → Suggested fix: <action>
```

Flag any instance where `state != Active` or `Ready != True` with a clear action item.
