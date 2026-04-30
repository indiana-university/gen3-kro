---
name: debug-kro
description: 'Diagnose a stuck, errored, or misbehaving KRO instance or RGD'
agent: agent
tools: ['terminalCommand', 'search/codebase', 'search']
argument-hint: 'KRO instance kind and name (e.g. "AwsGen3Foundation1 gen3")'
---

# Debug KRO Instance or RGD

## Inputs

- **Resource**: ${input:resource:Kind and name, e.g. "AwsGen3Foundation1 gen3"}
- **Namespace**: ${input:namespace:e.g. spoke1}

## Diagnosis Steps

### Step 1 — KRO Instance Status
```bash
kubectl get ${input:resource} -n ${input:namespace} -o yaml
```
Look for: `.status.conditions`, `.status.state`, and any error messages.

### Step 2 — KRO Controller Logs
```bash
kubectl logs -n kro -l app.kubernetes.io/name=kro --tail=50
```
Filter for the instance name and any reconciliation errors.

### Step 3 — ACK Resource Status
For each ACK resource in the RGD, check its conditions:
```bash
# Example for a VPC
kubectl get vpc -n ${input:namespace} -o yaml | grep -A5 conditions
```
`ACK.ResourceSynced: False` means the ACK controller rejected or is still creating the resource.

### Step 4 — ArgoCD Application Health
```bash
kubectl get application -n argocd
```
Look for `Degraded` or `OutOfSync` applications.

### Step 5 — Bridge ConfigMaps
```bash
kubectl get configmaps -n ${input:namespace}
kubectl get configmap <bridge-name> -n ${input:namespace} -o yaml
```
Empty bridge values (e.g., `vpcId: ""`) mean the upstream resource is not yet ready.

## Common Fixes

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Instance stuck in `Progressing` | Upstream resource not ready | Check ACK resource status + logs |
| `externalRef` not resolving | Bridge ConfigMap missing or empty | Check producer RGD is synced |
| ArgoCD `OutOfSync` | RGD CRD not yet registered | Wait for KRO controller (wave -30) |
| `ACK.ResourceSynced: False` | AWS API error | Check ACK controller logs in `ack` namespace |
| Instance deleted but AWS resource remains | `deletionPolicy: retain` | Expected — manual cleanup needed |
