---
name: kro-rgd-debug
description: 'Debug a stuck, errored, or misbehaving KRO instance or RGD in gen3-kro. Use when: KRO instance is not Ready, ResourceGraphDefinition shows errors, ACK resource is stuck, bridge ConfigMap is missing or empty, instance status shows unknown or false conditions, user asks why a KRO resource is broken, or asks to diagnose KRO.'
allowed-tools: Bash
---

# KRO RGD Debug

Diagnose and resolve issues with KRO ResourceGraphDefinitions and their instances in gen3-kro.

## Step 1 — Identify the instance and namespace

```bash
# List all KRO instances across namespaces
kubectl get resourcegraphdefinitions -A
kubectl get all -n <namespace>
```

## Step 2 — Check KRO instance conditions

```bash
# Replace KIND and NAME with the actual resource
kubectl describe <kind> <name> -n <namespace>

# Look for:
# - .status.conditions[].type == "Ready" && .status.conditions[].status != "True"
# - .status.conditions[].message  ← this has the root cause
```

## Step 3 — Inspect the graph reconciliation status

```bash
kubectl get <kind> <name> -n <namespace> -o jsonpath='{.status}' | jq .
```

Key fields to check:
- `state` — should be `Active` when healthy
- `conditions` — look for `type: ReconcilerReady` or `type: GraphVerified`
- `topologicalOrder` — lists the resources in dependency order

## Step 4 — Check individual ACK resource status

```bash
# For each ACK resource (e.g. RDS DBInstance, EC2 SecurityGroup):
kubectl get dbinstances.rds.services.k8s.aws -n <namespace>
kubectl describe dbinstances.rds.services.k8s.aws <name> -n <namespace>

# Look for ACK conditions:
# - ACK.ResourceSynced == True (means AWS agrees)
# - ACK.Terminal == True (means a permanent error — needs manual fix)
```

## Step 5 — Check bridge ConfigMaps

```bash
# List bridge ConfigMaps in the namespace
kubectl get configmaps -n <namespace> | grep -E 'Bridge|bridge'

# Inspect a bridge ConfigMap
kubectl get configmap <bridgeName> -n <namespace> -o yaml

# Keys to verify (examples):
# - foundationBridge: vpcId, privateSubnetIds, publicSubnetIds
# - databasePrepBridge: dbSubnetGroupName, dbSecurityGroupId
# - storageBridge: loggingBucketArn, dataBucketArn
```

## Step 6 — Check KRO controller logs

```bash
kubectl logs -n kro-system -l app.kubernetes.io/name=kro --tail=100 | grep -E 'ERROR|WARN|<namespace>|<kind>'
```

## Step 7 — Check ACK controller logs

```bash
# Find the relevant ACK controller (e.g. ack-rds-controller)
kubectl get pods -n ack-system
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-rds-controller --tail=100 | grep -E 'ERROR|WARN'
```

## Step 8 — Common root causes and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `bridge ConfigMap not found` | Upstream RGD not ready | Check upstream instance status |
| `ACK.Terminal == True` | AWS API rejected — quota, permissions, or invalid value | Check ACK condition message; fix the value |
| `state: Pending` indefinitely | Dependency cycle or missing readyWhen | Review RGD resource order; check `readyWhen` expressions |
| Status field uses `.?field` optional chain evaluates to orValue string | Resource created but field not populated | Wait for AWS propagation; re-check after 60s |
| `namespaceNotFound` | KRO namespace not created | Check ArgoCD sync; ensure ClusterResources1 instance is synced |
| `image pull error` on KRO controller | Wrong image digest | Upgrade KRO via ArgoCD addon |

## Step 9 — Force ArgoCD re-sync if needed

```bash
argocd app sync <app-name> --force
# OR via ArgoCD UI: Hard Refresh → Sync
```

## Output Format

Provide a concise diagnosis:
1. **Root cause** — one sentence
2. **Evidence** — the specific condition message or field value
3. **Fix** — exact command(s) or YAML change needed
4. **Verification** — how to confirm the fix worked
