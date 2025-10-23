# ArgoCD Configuration

This directory contains ArgoCD ApplicationSets, configuration files, and deployment definitions for the Gen3 KRO platform's GitOps workflow.

## Overview

The Gen3 KRO platform uses ArgoCD for continuous deployment with a wave-based deployment strategy:

- **Wave 0**: Platform addons (KRO, ACK controllers, External Secrets)
- **Wave 1**: ResourceGraphDefinitions (infrastructure schemas)
- **Wave 2**: Graph instances (infrastructure provisioning)
- **Wave 3**: Application workloads (Gen3 commons)

## Directory Structure

```
argocd/
├── bootstrap/              # Bootstrap ApplicationSets (deployed by Terraform)
│   ├── hub-addons.yaml    # Wave 0: Hub cluster addons
│   ├── spoke-addons.yaml  # Wave 0: Spoke cluster addons
│   ├── graphs.yaml        # Wave 1: ResourceGraphDefinitions
│   ├── graph-instances.yaml # Wave 2: Infrastructure instances
│   └── app-instances.yaml # Wave 3: Application workloads
├── hub/                    # Hub cluster configuration
│   └── addons/
│       ├── catalog.yaml   # Addon chart metadata
│       ├── enablement.yaml # Addon toggles
│       └── values.yaml    # Addon Helm values
├── spokes/                 # Spoke cluster configurations
│   └── <spoke-name>/
│       ├── addons/        # Spoke-specific addon config
│       ├── infrastructure/ # Infrastructure overlays
│       ├── cluster-values/ # Cluster-specific values
│       └── <gen3-instance>/ # Gen3 application configs
├── graphs/                 # ResourceGraphDefinitions
│   └── aws/
│       ├── vpc-network-rgd.yaml
│       ├── eks-cluster-rgd.yaml
│       └── iam-roles-rgd.yaml
├── charts/                 # Helm chart templates
│   └── addons-appset/
└── plans/                  # Deployment planning docs
```

## ApplicationSet Hierarchy

### Bootstrap Process

The Gen3 KRO platform uses a **bootstrap ApplicationSet pattern** to manage all ArgoCD ApplicationSets:

1. **Terraform** deploys a single bootstrap ApplicationSet (from `terraform/combinations/hub/applicationsets.yaml`)
2. **Bootstrap ApplicationSet** uses a directory generator with `recurse: true` to sync `argocd/bootstrap/` directory
3. **Five Child ApplicationSets** are created from YAML files in the bootstrap directory:
   - `hub-addons.yaml` - Platform addons for hub cluster (Wave 0)
   - `spoke-addons.yaml` - Platform addons for spoke clusters (Wave 0)
   - `graphs.yaml` - ResourceGraphDefinitions (Wave 1)
   - `graph-instances.yaml` - Infrastructure instances (Wave 2)
   - `app-instances.yaml` - Application workloads (Wave 3)
4. **Each child ApplicationSet** deploys resources according to its wave number and generator configuration

```
┌──────────────────────────────────────────────────────┐
│  Terraform (Hub Combination)                         │
│  Deploys: bootstrap ApplicationSet (single YAML)     │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────────┐
│  Bootstrap ApplicationSet                                  │
│  Type: Directory (recurse: true)                           │
│  Syncs: argocd/bootstrap/*.yaml → Creates 5 ApplicationSets│
└─┬────┬──────┬───────────┬──────────────┬──────────────────┘
  │    │      │           │              │
  │    │      │           │              │
  ▼    ▼      ▼           ▼              ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐ ┌──────────┐
│  hub-  │ │ spoke- │ │graphs  │ │  graph-  │ │   app-   │
│addons  │ │addons  │ │  .yaml │ │instances │ │instances │
│ .yaml  │ │ .yaml  │ │        │ │  .yaml   │ │  .yaml   │
└────────┘ └────────┘ └────────┘ └──────────┘ └──────────┘
 Wave 0     Wave 0     Wave 1      Wave 2       Wave 3
    │          │          │            │            │
    ▼          ▼          ▼            ▼            ▼
  Hub       Spoke       RGD      Infrastructure  Applications
 Addons     Addons   Definitions    Instances     (Gen3)
```

## Configuration Files

### Hub Addon Configuration

#### catalog.yaml

Defines addon metadata: Helm repository URLs, chart versions, and chart names.

```yaml
items:
  - addon: ec2
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/ec2-chart
    revision: v1.7.0
    chartPath: ec2-chart

  - addon: kro
    repoURL: https://kro-run.github.io/kro
    revision: 0.1.0
    chartPath: kro

  - addon: external-secrets
    repoURL: https://charts.external-secrets.io
    revision: 0.9.13
    chartPath: external-secrets
```

#### enablement.yaml

Controls which addons are deployed on the hub cluster.

```yaml
cluster: hub
enablement:
  ec2:
    enabled: true
  eks:
    enabled: true
  kro:
    enabled: true  # Must be enabled on hub
  external-secrets:
    enabled: true
```

#### values.yaml

Provides Helm values for each addon.

```yaml
global:
  roleArns:
    ec2: "arn:aws:iam::123456789012:role/hub-ack-ec2"
    eks: "arn:aws:iam::123456789012:role/hub-ack-eks"
  namespaces:
    ack: "ack-system"

values:
  ec2:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.ec2}}"
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
```

### Spoke Configuration

Each spoke has its own directory: `spokes/<spoke-name>/`

#### addons/

Spoke-specific addon configuration (overrides hub defaults).

**enablement.yaml**:
```yaml
cluster: spoke1
enablement:
  ec2:
    enabled: true
  eks:
    enabled: false  # Spokes typically don't need EKS controller
  kro:
    enabled: false  # KRO only runs on hub
```

**values.yaml**:
```yaml
global:
  roleArns:
    ec2: "arn:aws:iam::987654321098:role/spoke1-ec2"

values:
  ec2:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.ec2}}"
```

#### infrastructure/

Kustomize overlays for infrastructure provisioning.

**kustomization.yaml**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../../shared/instances
patches:
  - path: values.yaml
    target:
      kind: EksCluster
```

**values.yaml**:
```yaml
apiVersion: v1alpha1
kind: EksCluster
metadata:
  name: spoke1-cluster
spec:
  name: spoke1
  accountId: "987654321098"
  region: us-west-2
  vpc:
    vpcCidr: "10.1.0.0/16"
```

#### <gen3-instance>/

Gen3 application configurations.

**templates/app.yaml**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gen3-covid19prod
  namespace: argocd
spec:
  project: default
  sources:
    - path: helm/gen3
      repoURL: https://github.com/uc-cdis/gen3-helm
      targetRevision: main
      helm:
        releaseName: gen3-covid19prod
        valueFiles:
          - $values/values/values.yaml
    - repoURL: https://github.com/indiana-university/gen3-kro.git
      targetRevision: main
      ref: values
  destination:
    server: "https://kubernetes.default.svc"
    namespace: covid19prod-helm
  syncPolicy:
    automated: {}
```

## Wave-Based Deployment

### Wave 0: Addons

**File**: `bootstrap/hub-addons.yaml`, `bootstrap/spoke-addons.yaml`

**Purpose**: Deploy platform prerequisites

**Addons**:
- **KRO** (hub only): Required for ResourceGraphDefinitions
- **ACK Controllers**: AWS resource management
- **External Secrets**: Secret management
- **Kyverno**: Policy enforcement

**Generator Strategy**: 3-way merge
1. Catalog: Defines available addons
2. Enablement: Determines which are enabled
3. Values: Provides configuration

**Critical**: KRO must complete before Wave 1

### Wave 1: Graphs

**File**: `bootstrap/graphs.yaml`

**Purpose**: Deploy ResourceGraphDefinitions (CRDs)

**Target**: Hub cluster only

**Resources**: `argocd/graphs/aws/*.yaml`
- VPC network RGD
- EKS cluster RGD
- IAM roles RGD

**Dependency**: Requires KRO from Wave 0

### Wave 2: Graph Instances

**File**: `bootstrap/graph-instances.yaml`

**Purpose**: Deploy infrastructure instances

**Target**: Hub cluster (instances provision spoke infrastructure)

**Resources**: `argocd/spokes/*/infrastructure/`

**Process**:
1. ArgoCD deploys instance manifests to hub
2. KRO processes instances against RGDs
3. ACK controllers provision AWS resources in spoke accounts
4. Spoke clusters become available

**Dependency**: Requires RGDs from Wave 1

### Wave 3: App Instances

**File**: `bootstrap/app-instances.yaml`

**Purpose**: Deploy Gen3 workloads

**Target**: Spoke clusters

**Resources**: `argocd/spokes/*/<gen3-instance>/`

**Dependency**: Requires spoke clusters from Wave 2

## ApplicationSet Patterns

### Git Directory Generator

Discovers spokes dynamically:

```yaml
generators:
  - git:
      repoURL: https://github.com/indiana-university/gen3-kro.git
      revision: main
      directories:
        - path: argocd/spokes/*
```

### Cluster Generator

Targets specific cluster types:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          fleet_member: control-plane  # Hub only
```

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          fleet_member: spoke  # Spokes only
```

### Matrix Generator

Combines generators:

```yaml
generators:
  - matrix:
      generators:
        - git:
            directories:
              - path: argocd/spokes/*
        - clusters:
            selector:
              matchLabels:
                fleet_member: control-plane
```

### Merge Generator

3-way merge for addons:

```yaml
generators:
  - merge:
      mergeKeys:
        - addon
      generators:
        - git:
            files:
              - path: argocd/hub/addons/catalog.yaml
        - git:
            files:
              - path: argocd/hub/addons/enablement.yaml
        - git:
            files:
              - path: argocd/hub/addons/values.yaml
```

## Adding Components

### Add New Spoke

1. **Create directory**:
   ```bash
   mkdir -p argocd/spokes/spoke2/{addons,infrastructure,cluster-values}
   ```

2. **Copy structure from existing spoke**:
   ```bash
   cp -r argocd/spokes/spoke1/addons argocd/spokes/spoke2/
   cp -r argocd/spokes/spoke1/infrastructure argocd/spokes/spoke2/
   ```

3. **Update configuration**:
   - `addons/enablement.yaml`: Set cluster name
   - `addons/values.yaml`: Update IAM role ARNs
   - `infrastructure/values.yaml`: Set account ID, region, VPC CIDR

4. **Commit and push**:
   ```bash
   git add argocd/spokes/spoke2
   git commit -m "Add spoke2 cluster configuration"
   git push
   ```

5. **ArgoCD auto-discovers** spoke2 within minutes

### Add New Addon

1. **Add to catalog** (`hub/addons/catalog.yaml`):
   ```yaml
   - addon: new-addon
     repoURL: https://charts.example.com
     revision: 1.0.0
     chartPath: new-addon
   ```

2. **Enable in hub** (`hub/addons/enablement.yaml`):
   ```yaml
   new-addon:
     enabled: true
   ```

3. **Add values** (`hub/addons/values.yaml`):
   ```yaml
   new-addon:
     namespace: new-addon-system
     config:
       key: value
   ```

4. **Optionally enable in spokes**:
   ```bash
   # Edit spokes/*/addons/enablement.yaml
   ```

5. **Commit and push**

### Add New ResourceGraphDefinition

1. **Create RGD file**:
   ```bash
   cat > argocd/graphs/aws/new-resource-rgd.yaml <<EOF
   apiVersion: kro.run/v1alpha1
   kind: ResourceGraph
   metadata:
     name: newresource
   spec:
     # ... RGD definition ...
   EOF
   ```

2. **Commit and push**

3. **ArgoCD deploys** to hub in Wave 1

## Verification

### Check ApplicationSets

```bash
kubectl get applicationsets -n argocd
```

Expected:
- `hub-addons`
- `spoke-addons`
- `graphs`
- `graph-instances`
- `app-instances`

### Check Generated Applications

```bash
kubectl get applications -n argocd
```

Expected format:
- `hub-<addon-name>` (Wave 0)
- `<spoke>-<addon-name>` (Wave 0)
- `<rgd-name>-hub` (Wave 1)
- `<spoke>-graph-instances` (Wave 2)
- `<spoke>-<gen3-instance>` (Wave 3)

### Check Sync Status

```bash
kubectl get applications -n argocd -o custom-columns=\
NAME:.metadata.name,\
SYNC:.status.sync.status,\
HEALTH:.status.health.status,\
WAVE:.metadata.annotations."argocd\.argoproj\.io/sync-wave"
```

All should be:
- SYNC: `Synced`
- HEALTH: `Healthy`

### Check Logs

```bash
# ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller

# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Troubleshooting

### Application Out of Sync

**Symptom**: Application stuck in `OutOfSync` state

**Check**:
```bash
kubectl describe application <app-name> -n argocd
kubectl get application <app-name> -n argocd -o yaml | grep -A 20 status
```

**Common Causes**:
- Git repository inaccessible
- Invalid YAML syntax
- Missing dependencies
- Resource conflicts

**Solution**:
```bash
# Force refresh
argocd app get <app-name> --refresh

# Manual sync
argocd app sync <app-name>
```

### Generator Not Finding Resources

**Symptom**: Expected applications not created

**Check**:
```bash
kubectl get applicationset <appset-name> -n argocd -o yaml
```

Look at `status.conditions` for errors

**Common Causes**:
- Incorrect Git path
- Wrong cluster label selector
- Merge generator key mismatch

**Solution**: Verify generator configuration matches actual repo structure

### Wave Dependencies Not Working

**Symptom**: Wave N deploys before Wave N-1 completes

**Check**:
```bash
kubectl get applications -n argocd --sort-by=.metadata.annotations."argocd\.argoproj\.io/sync-wave"
```

**Solution**: Ensure `sync-wave` annotations are correct in ApplicationSet metadata

### KRO Instance Not Reconciling

**Symptom**: Graph instance stuck in `Pending` state

**Check**:
```bash
kubectl describe ekscluster <instance-name>
kubectl logs -n kro-system -l app=kro-controller
```

**Common Causes**:
- RGD not installed (Wave 1 incomplete)
- ACK controller not running (Wave 0 incomplete)
- IAM permissions missing

## Best Practices

### 1. Use Sync Waves

Always annotate ApplicationSets with sync waves:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

### 2. Keep Configurations DRY

Use kustomize overlays to avoid duplication:
- Base: `argocd/shared/instances/`
- Overlays: `argocd/spokes/*/infrastructure/`

### 3. Use Cluster Labels

Label cluster secrets for targeting:

```yaml
metadata:
  labels:
    fleet_member: control-plane  # or: spoke
    environment: production
```

### 4. Validate Before Commit

```bash
# Validate YAML
kubectl apply --dry-run=client -f argocd/bootstrap/

# Validate kustomize
kustomize build argocd/spokes/spoke1/infrastructure/

# Lint Helm values
helm lint --values argocd/hub/addons/values.yaml
```

### 5. Use Git Branches

- `main`: Production configurations
- `staging`: Testing configurations
- Feature branches: Development

Update ArgoCD cluster secret `targetRevision` annotation to switch branches.

## See Also

- [Terragrunt Deployment Guide](../docs/setup-terragrunt.md)
- [Adding Cluster Addons Guide](../docs/add-cluster-addons.md)
- [Hub Combination](../terraform/combinations/hub/README.md)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [KRO Documentation](https://kro.run/)
