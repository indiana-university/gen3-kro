---
name: spoke-onboard
description: 'Onboard a new spoke account to the gen3-kro fleet'
agent: agent
tools: ['search/codebase', 'edit/editFiles', 'search']
argument-hint: 'Spoke name (e.g. "spoke2") and hostname (e.g. "myapp.example.com")'
---

# Onboard a New Spoke

## Inputs

- **Spoke name**: ${input:spokeName:e.g. spoke2}
- **Hostname**: ${input:hostname:e.g. myapp.example.com}
- **AWS region**: ${input:region:e.g. us-east-1}

## Steps

### 1. Fleet directory structure
Create `argocd/fleet/${input:spokeName}/` mirroring the `spoke1` structure:
```
argocd/fleet/${input:spokeName}/
├── infrastructure/
│   ├── instances.yaml
│   └── infrastructure-values.yaml
├── cluster-level-resources/
│   ├── app.yaml
│   └── cluster-values.yaml
└── ${input:hostname}/
    ├── app.yaml
    └── values.yaml
```

### 2. Spoke IAM (Terragrunt)
Create `terragrunt/live/${input:spokeName}/` following the `spoke1` pattern.
Run `terragrunt apply` to create cross-account IAM roles.

### 3. Infrastructure instances
In `infrastructure/instances.yaml`, include the standard tier instances:
- Wave 15: AwsGen3Foundation1 (with `databaseEnabled`, `computeEnabled` flags)
- Wave 20: AwsGen3Storage1, AwsGen3Database1, AwsGen3Search1, AwsGen3Messaging1
- Wave 25: AwsGen3IAM1, AwsGen3Advanced1
- Wave 27: AwsGen3ClusterResources1
- Wave 30: AwsGen3Helm2 (or AwsGen3Helm1)

### 4. Namespace annotation
Ensure the spoke namespace has:
```yaml
annotations:
  services.k8s.aws/owner-account-id: "<injected at runtime>"
  services.k8s.aws/region: "${input:region}"
```

### 5. Verify
After committing, watch ArgoCD sync the new spoke:
```bash
kubectl get application -n argocd | grep ${input:spokeName}
```

Reference `docs/spoke-prerequisites.md` for full prerequisites checklist.
