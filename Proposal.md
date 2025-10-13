# ArgoCD Bootstrap Deployment Proposal - Comprehensive Guide

## Executive Summary
This proposal outlines the complete bootstrap deployment architecture for the Gen3 KRO platform. The bootstrap process deploys all applications, charts, and values in the `argocd/` folder through a hierarchical ApplicationSet structure that ensures proper ordering, dependency management, and scalability across hub and spoke clusters.

---

## 1. Architecture Overview

### 1.1 Deployment Hierarchy
```
Bootstrap ApplicationSet (Terraform-managed)
  ├── Wave 0: Addons ApplicationSet
  │   ├── KRO Controller (Hub)
  │   ├── ACK Controllers (Hub + Spokes)
  │   ├── External Secrets (Hub + Spokes)
  │   ├── Kyverno (Hub + Spokes)
  │   └── Other Platform Addons
  ├── Wave 1: Graphs ApplicationSet
  │   └── ResourceGraphDefinitions (Hub only)
  ├── Wave 2: Graph Instances ApplicationSet
  │   └── Infrastructure Instances (Hub, builds spoke infrastructure)
  └── Wave 3: Gen3 Instances ApplicationSet
      └── Gen3 Workload Apps (Spokes)
```

### 1.2 Cluster Topology
- **Hub Cluster**: Control plane with `fleet_member: control-plane` label
  - Runs KRO controller
  - Hosts ResourceGraphDefinitions
  - Manages infrastructure provisioning for spokes
  - Runs hub-specific controllers (e.g., IAM)
  
- **Spoke Clusters**: Workload clusters with `fleet_member: spoke` label
  - Run Gen3 instances and workloads
  - Use ACK controllers for AWS resource management
  - Receive infrastructure from hub-managed graphs

---

## 2. ApplicationSet Details

### 2.1 Bootstrap ApplicationSet
**Location**: `terraform/modules/root/applicationsets.yaml`  
**Purpose**: Root ApplicationSet that deploys all child ApplicationSets from `argocd/bootstrap/`

**Configuration**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: bootstrap
  namespace: argocd
spec:
  goTemplate: true
  syncPolicy:
    preserveResourcesOnDeletion: false
  generators:
  - clusters:
      selector:
        matchLabels:
          fleet_member: control-plane
  template:
    metadata:
      name: bootstrap
    spec:
      project: default
      source:
        repoURL: '{{.metadata.annotations.fleet_repo_url}}'
        path: '{{.metadata.annotations.fleet_repo_basepath}}{{.metadata.annotations.fleet_repo_path}}'
        targetRevision: '{{.metadata.annotations.fleet_repo_revision}}'
        directory:
          recurse: true  # Deploys all ApplicationSets in bootstrap/
          exclude: exclude/*
      destination:
        namespace: argocd
        name: '{{.name}}'
      syncPolicy:
        automated: {}
        syncOptions:
          - CreateNamespace=true
```

**Key Features**:
- Targets only hub cluster (`fleet_member: control-plane`)
- Uses cluster annotations for repo URL, path, and revision
- Recursively deploys all YAML files in bootstrap directory
- Automated sync ensures continuous deployment

---

### 2.2 Addons ApplicationSet (Wave 0)
**Location**: `argocd/bootstrap/addons.yaml`  
**Sync Wave**: 0 (deploys first)  
**Purpose**: Deploys platform addons including ACK controllers, KRO, external-secrets, and other infrastructure components

**Supported Controllers**:
- **ACK Controllers**: cloudtrail, cloudwatchlogs, ec2, efs, eks, iam, kms, opensearchservice, rds, route53, s3, secretsmanager, sns, sqs, wafv2
- **Platform Components**: external-secrets, kube-state-metrics, kro, kyverno, kyverno-policies, metrics-server

**Generator Strategy** (3-way merge):
1. **Catalog Generator**: Defines addon metadata (chart repo, version, path)
2. **Enablement Generator**: Determines which addons are enabled per cluster
3. **Values Generator**: Provides Helm values and configuration per addon/cluster

**Configuration Files**:

**Catalog** (`argocd/hub/addons/catalog.yaml`):
```yaml
items:
  - addon: cloudtrail
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/cloudtrail-chart
    revision: v1.0.5
    chartPath: cloudtrail-chart
  - addon: cloudwatchlogs
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/cloudwatchlogs-chart
    revision: v1.0.9
    chartPath: cloudwatchlogs-chart
  - addon: ec2
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/ec2-chart
    revision: v1.7.0
    chartPath: ec2-chart
  - addon: efs
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/efs-chart
    revision: v1.1.1
    chartPath: efs-chart
  - addon: eks
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/eks-chart
    revision: v1.9.3
    chartPath: eks-chart
  - addon: iam
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/iam-chart
    revision: v1.2.1
    chartPath: iam-chart
  - addon: kms
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/kms-chart
    revision: v1.0.8
    chartPath: kms-chart
  - addon: opensearchservice
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/opensearchservice-chart
    revision: v1.0.7
    chartPath: opensearchservice-chart
  - addon: rds
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/rds-chart
    revision: v1.5.0
    chartPath: rds-chart
  - addon: route53
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/route53-chart
    revision: v1.0.8
    chartPath: route53-chart
  - addon: s3
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/s3-chart
    revision: v1.0.11
    chartPath: s3-chart
  - addon: secretsmanager
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/secretsmanager-chart
    revision: v1.0.3
    chartPath: secretsmanager-chart
  - addon: sns
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/sns-chart
    revision: v1.0.10
    chartPath: sns-chart
  - addon: sqs
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/sqs-chart
    revision: v1.0.12
    chartPath: sqs-chart
  - addon: wafv2
    repoURL: oci://public.ecr.aws/aws-controllers-k8s/wafv2-chart
    revision: v1.0.5
    chartPath: wafv2-chart
  - addon: kro
    repoURL: https://kro-run.github.io/kro
    revision: 0.1.0
    chartPath: kro
  - addon: external-secrets
    repoURL: https://charts.external-secrets.io
    revision: 0.9.13
    chartPath: external-secrets
  - addon: kube-state-metrics
    repoURL: https://prometheus-community.github.io/helm-charts
    revision: 5.16.0
    chartPath: kube-state-metrics
  - addon: kyverno
    repoURL: https://kyverno.github.io/kyverno
    revision: 3.1.4
    chartPath: kyverno
  - addon: kyverno-policies
    repoURL: https://kyverno.github.io/kyverno
    revision: 3.1.4
    chartPath: kyverno-policies
  - addon: metrics-server
    repoURL: https://kubernetes-sigs.github.io/metrics-server
    revision: 3.11.0
    chartPath: metrics-server
```

**Enablement** (`argocd/hub/addons/enablement.yaml`):
```yaml
cluster: hub
enablement:
  cloudtrail:
    enabled: true
  cloudwatchlogs:
    enabled: true
  ec2:
    enabled: true
  efs:
    enabled: true
  eks:
    enabled: true
  iam:
    enabled: true
  kms:
    enabled: true
  opensearchservice:
    enabled: true
  rds:
    enabled: true
  route53:
    enabled: true
  s3:
    enabled: true
  secretsmanager:
    enabled: true
  sns:
    enabled: true
  sqs:
    enabled: true
  wafv2:
    enabled: true
  kro:
    enabled: true  # CRITICAL: Must be enabled on hub
  external-secrets:
    enabled: true
  kube-state-metrics:
    enabled: true
  kyverno:
    enabled: true
  kyverno-policies:
    enabled: true
  metrics-server:
    enabled: true
```

**Values** (`argocd/hub/addons/values.yaml`):
```yaml
global:
  roleArns:
    cloudtrail: "arn:aws:iam::123456789012:role/hub-ack-cloudtrail"
    cloudwatchlogs: "arn:aws:iam::123456789012:role/hub-ack-cloudwatchlogs"
    ec2: "arn:aws:iam::123456789012:role/hub-ack-ec2"
    efs: "arn:aws:iam::123456789012:role/hub-ack-efs"
    eks: "arn:aws:iam::123456789012:role/hub-ack-eks"
    iam: "arn:aws:iam::123456789012:role/hub-ack-iam"
    kms: "arn:aws:iam::123456789012:role/hub-ack-kms"
    opensearchservice: "arn:aws:iam::123456789012:role/hub-ack-opensearchservice"
    rds: "arn:aws:iam::123456789012:role/hub-ack-rds"
    route53: "arn:aws:iam::123456789012:role/hub-ack-route53"
    s3: "arn:aws:iam::123456789012:role/hub-ack-s3"
    secretsmanager: "arn:aws:iam::123456789012:role/hub-ack-secretsmanager"
    sns: "arn:aws:iam::123456789012:role/hub-ack-sns"
    sqs: "arn:aws:iam::123456789012:role/hub-ack-sqs"
    wafv2: "arn:aws:iam::123456789012:role/hub-ack-wafv2"
  namespaces:
    ack: "ack-system"

values:
  cloudtrail:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.cloudtrail}}"
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  cloudwatchlogs:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "{{.Values.global.roleArns.cloudwatchlogs}}"
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
      requests:
        cpu: 100m
        memory: 128Mi
  # ... (similar structure for all ACK controllers)
  kro:
    namespace: kro-system
  external-secrets:
    namespace: external-secrets-system
  kube-state-metrics:
    namespace: kube-system
```

**ApplicationSet Template**:
```yaml
template:
  metadata:
    name: '{{ .cluster }}-{{ .addon }}'
    labels:
      app.kubernetes.io/part-of: addons
      cluster: '{{ .cluster }}'
      addon: '{{ .addon }}'
  spec:
    project: default
    source:
      repoURL: '{{ .repoURL }}'
      targetRevision: '{{ .revision }}'
      path: '{{ .chartPath }}'
      helm:
        values: |
          {{ toYaml .addonValues }}
    destination:
      name: '{{ .cluster }}'
      namespace: '{{ .addonValues.namespace | default "ack-system" }}'
    syncPolicy:
      automated: {}
```

**Key Features**:
- Merge generator ensures addons deploy only when catalog, enablement, and values all match
- Per-cluster customization via spoke-specific enablement/values files
- IAM role ARNs templated from global values
- Resource limits standardized across controllers
- KRO controller deployed first (Wave 0) to enable RGDs in Wave 1

---

### 2.3 Graphs ApplicationSet (Wave 1)
**Location**: `argocd/bootstrap/graphs.yaml`  
**Sync Wave**: 1 (after addons, specifically after KRO)  
**Purpose**: Deploys ResourceGraphDefinitions (RGDs) to hub cluster

**Target Resources**:
- `argocd/shared/graphs/aws/*.yaml`: RGD definitions
  - `efs-rgd.yaml`: EFS resource graph
  - `eks-basic-rgd.yaml`: Basic EKS cluster
  - `eks-cluster-rgd.yaml`: Full EKS cluster with networking
  - `iam-addons-rgd.yaml`: IAM roles for addons
  - `iam-roles-rgd.yaml`: IAM role definitions
  - `vpc-network-rgd.yaml`: VPC and networking

**Configuration**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: graphs
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  goTemplate: true
  generators:
  - clusters:
      selector:
        matchLabels:
          fleet_member: control-plane
  - git:
      repoURL: https://github.com/indiana-university/gen3-kro.git
      revision: staging
      files:
        - path: argocd/shared/graphs/**/*.yaml
  template:
    metadata:
      name: '{{.path.basename}}-{{.name}}'
      labels:
        app.kubernetes.io/part-of: graphs
        cluster: '{{.name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/indiana-university/gen3-kro.git
        targetRevision: staging
        path: '{{.path}}'
      destination:
        name: '{{.name}}'
        namespace: default
      syncPolicy:
        automated: {}
```

**Key Features**:
- Deploys only to hub cluster
- Git file generator scans `shared/graphs/**/*.yaml` for all RGDs
- Each RGD becomes a separate ArgoCD Application
- Requires KRO controller (from Wave 0) to be running
- RGDs define infrastructure schemas; instances created in Wave 2

---

### 2.4 Graph Instances ApplicationSet (Wave 2)
**Location**: `argocd/bootstrap/graph-instances.yaml`  
**Sync Wave**: 2 (after graphs)  
**Purpose**: Deploys kustomized infrastructure instances to hub, which provision spoke infrastructure

**Target Resources**:
- `argocd/shared/instances/eks-cluster-instance.yaml`: Base EKS cluster instance
- `argocd/shared/instances/kustomization.yaml`: Base kustomization
- `argocd/spokes/*/infrastructure/kustomization.yaml`: Spoke-specific overlays
- `argocd/spokes/*/infrastructure/values.yaml`: Spoke-specific patches

**Configuration**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: graph-instances
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  goTemplate: true
  generators:
  - matrix:
      generators:
        - git:
            repoURL: https://github.com/indiana-university/gen3-kro.git
            revision: staging
            directories:
              - path: argocd/spokes/*
        - clusters:
            selector:
              matchLabels:
                fleet_member: control-plane
  template:
    metadata:
      name: '{{ .path.basename }}-graph-instances'
      labels:
        app: graph-instances
        cluster: '{{ .path.basename }}'
    spec:
      project: default
      source:
        repoURL: https://github.com/indiana-university/gen3-kro.git
        targetRevision: staging
        path: '{{ .path.path }}/infrastructure'
        kustomize:
          commonLabels:
            cluster: '{{ .path.basename }}'
      destination:
        server: '{{ .server }}'
        namespace: default
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
        syncOptions:
          - CreateNamespace=false
```

**Kustomization Structure**:

**Base** (`argocd/shared/instances/kustomization.yaml`):
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - eks-cluster-instance.yaml
```

**Base Instance** (`argocd/shared/instances/eks-cluster-instance.yaml`):
```yaml
apiVersion: v1alpha1
kind: EksCluster
metadata:
  name: template-cluster
  namespace: default
spec:
  name: template
  tenant: auto1
  environment: staging
  region: us-west-2
  k8sVersion: "1.32"
  accountId: "REPLACE_ACCOUNT_ID"
  managementAccountId: "REPLACE_HUB_ACCOUNT_ID"
  adminRoleName: "Admin"
  fleetSecretManagerSecretNameSuffix: "argocd-secret"
  domainName: "cluster.example.com"
  vpc:
    create: true
    vpcCidr: "10.0.0.0/16"
    publicSubnet1Cidr: "10.0.1.0/24"
    publicSubnet2Cidr: "10.0.2.0/24"
    privateSubnet1Cidr: "10.0.11.0/24"
    privateSubnet2Cidr: "10.0.12.0/24"
  workloads: "false"
  gitops:
    enabled: true
    repoUrl: "https://github.com/indiana-university/gen3-kro.git"
    repoPath: "argocd/bootstrap"
    repoRevision: "staging"
```

**Overlay** (`argocd/spokes/spoke1/infrastructure/kustomization.yaml`):
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

**Patch** (`argocd/spokes/spoke1/infrastructure/values.yaml`):
```yaml
apiVersion: v1alpha1
kind: EksCluster
metadata:
  name: spoke1-cluster
spec:
  name: spoke1
  accountId: "987654321098"
  region: us-west-2
  domainName: "spoke1.example.com"
  vpc:
    vpcCidr: "10.1.0.0/16"
    publicSubnet1Cidr: "10.1.1.0/24"
    publicSubnet2Cidr: "10.1.2.0/24"
    privateSubnet1Cidr: "10.1.11.0/24"
    privateSubnet2Cidr: "10.1.12.0/24"
```

**Key Features**:
- Deploys to hub cluster (instances run on hub, provision infrastructure on spokes)
- Git directory generator discovers all spokes
- Kustomize overlays allow per-spoke customization
- Matrix generator creates one app per spoke
- Requires RGDs from Wave 1
- **IMPORTANT**: Instances are deployed to hub but create resources on spoke AWS accounts

---

### 2.5 Gen3 Instances ApplicationSet (Wave 3)
**Location**: `argocd/bootstrap/gen3-instances.yaml`  
**Sync Wave**: 3 (after infrastructure)  
**Purpose**: Deploys Gen3 workload applications to spoke clusters

**Target Resources**:
- `argocd/spokes/*/sample.gen3.url.org/templates/app.yaml`: Gen3 Application manifests
- `argocd/spokes/*/sample.gen3.url.org/values/*.yaml`: Gen3 configuration values

**Configuration**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gen3-instances
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  goTemplate: true
  generators:
  - matrix:
      generators:
      - clusters:
          selector:
            matchLabels:
              fleet_member: spoke
      - git:
          repoURL: https://github.com/indiana-university/gen3-kro.git
          revision: staging
          files:
            - path: argocd/spokes/*/sample.gen3.url.org/templates/app.yaml
  template:
    metadata:
      name: '{{.name}}-gen3-instance'
      labels:
        app: gen3-instance
        cluster: '{{.name}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/indiana-university/gen3-kro.git
        targetRevision: staging
        path: '{{.path.dirname}}'
      destination:
        server: '{{.server}}'
        namespace: default
      syncPolicy:
        automated: {}
```

**Gen3 Application Structure** (`sample.gen3.url.org/templates/app.yaml`):
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
      targetRevision: feat/deployment-canary
      helm:
        releaseName: gen3-covid19prod
        valueFiles:
          - $values/values/values.yaml
    - repoURL: https://github.com/indiana-university/gen3-kro.git
      targetRevision: staging
      ref: values
  destination:
    server: "https://kubernetes.default.svc"
    namespace: covid19prod-helm
  syncPolicy:
    automated: {}
    syncOptions:
    - CreateNamespace=true
```

**Key Features**:
- Deploys to spoke clusters only
- Git file generator discovers Gen3 instances across all spokes
- Matrix generator creates one app per spoke/instance combination
- Waits for infrastructure (Wave 2) before deploying workloads
- Multi-source support for Gen3 Helm charts + gitops values

---

## 3. Deployment Flow

### 3.1 Initial Bootstrap
1. **Terraform Apply**: Deploys bootstrap ApplicationSet to hub cluster
2. **Bootstrap Sync**: ArgoCD syncs `argocd/bootstrap/` directory
3. **ApplicationSet Discovery**: Bootstrap discovers and deploys 4 child ApplicationSets

### 3.2 Sync Wave Execution
```
Wave 0 (Addons):
  └─> KRO Controller (hub) ─────────────┐
  └─> ACK Controllers (hub+spokes) ──────┤
  └─> External Secrets (hub+spokes) ─────┤
  └─> Kyverno (hub+spokes) ──────────────┤
  └─> Metrics Server (hub+spokes) ───────┴─> Ready for Wave 1

Wave 1 (Graphs):
  └─> RGD Definitions (hub) ────────────────> Ready for Wave 2

Wave 2 (Graph Instances):
  └─> Infrastructure Instances (hub) ───────> Provisions spoke clusters
                                          └──> Ready for Wave 3

Wave 3 (Gen3 Instances):
  └─> Gen3 Workloads (spokes) ─────────────> Applications running
```

### 3.3 Critical Dependencies
- **KRO before RGDs**: KRO controller must be running (Wave 0) before RGDs can be applied (Wave 1)
- **RGDs before Instances**: RGDs must exist before instances can be created (Wave 2)
- **Infrastructure before Workloads**: Spoke clusters must be provisioned before Gen3 apps deploy (Wave 3)
- **ACK Controllers**: Required for AWS resource management on both hub and spokes

### 3.4 Update Flow
1. **Config Change**: Update enablement/values/catalog in git
2. **Git Poll**: ArgoCD detects change via git generator
3. **Application Update**: Affected applications re-sync automatically
4. **Health Check**: ArgoCD validates deployment health

---

## 4. Configuration Files Reference

### 4.1 Hub Configuration
```
argocd/hub/
├── addons/
│   ├── catalog.yaml       # Addon chart metadata (repo URLs, versions, chart names)
│   ├── enablement.yaml    # Hub addon toggles (which addons to deploy)
│   └── values.yaml        # Hub addon Helm values (IAM roles, resources, config)
```

**Purpose**:
- **catalog.yaml**: Single source of truth for available addons and their chart locations
- **enablement.yaml**: Controls which addons are active on the hub cluster
- **values.yaml**: Customizes addon deployments with hub-specific config (IAM roles, namespaces, etc.)

### 4.2 Spoke Configuration
```
argocd/spokes/spoke1/
├── addons/
│   ├── catalog.yaml       # Spoke addon catalog (optional, inherits from hub if missing)
│   ├── enablement.yaml    # Spoke addon toggles (e.g., disable KRO, enable ACK controllers)
│   └── values.yaml        # Spoke addon Helm values (spoke-specific IAM roles, config)
├── infrastructure/
│   ├── kustomization.yaml # Infrastructure overlay (references shared/instances)
│   └── values.yaml        # Spoke-specific patches (account ID, VPC CIDR, region)
└── sample.gen3.url.org/
    ├── templates/
    │   └── app.yaml       # Gen3 Application manifest (ArgoCD App-of-Apps)
    └── values/
        ├── values.yaml    # Gen3 Helm values (portal config, services)
        └── portal/
            ├── gitops.json
            └── css/
```

**Purpose**:
- **addons/**: Per-spoke addon configuration (spokes typically disable KRO, enable ACK)
- **infrastructure/**: Kustomize overlay for spoke cluster provisioning
- **sample.gen3.url.org/**: Gen3 workload application definitions

### 4.3 Shared Resources
```
argocd/shared/
├── graphs/
│   └── aws/
│       ├── efs-rgd.yaml              # RGD for EFS file systems
│       ├── eks-cluster-rgd.yaml      # RGD for full EKS cluster + networking
│       ├── iam-addons-rgd.yaml       # RGD for addon IAM roles
│       ├── iam-roles-rgd.yaml        # RGD for IAM role definitions
│       └── vpc-network-rgd.yaml      # RGD for VPC and subnets
└── instances/
    ├── eks-cluster-instance.yaml     # Base EKS cluster instance template
    └── kustomization.yaml            # Base kustomization referencing instance
```

**Purpose**:
- **graphs/aws/**: ResourceGraphDefinitions (CRDs) that define infrastructure schemas
- **instances/**: Shared instance templates customized via kustomize overlays

---

## 5. Key Design Principles

### 5.1 GitOps-Native
- All configuration in Git
- ArgoCD auto-syncs changes
- No manual kubectl/helm commands required
- Declarative desired state

### 5.2 Declarative and Idempotent
- ApplicationSets define desired state
- ArgoCD reconciles to match
- Safe to re-run/re-apply
- Self-healing on drift

### 5.3 Scalable and DRY
- Git generators enable dynamic spoke discovery
- Shared bases + overlays prevent duplication
- Adding a spoke = create folder + push to git
- No hardcoded cluster lists

### 5.4 Dependency-Aware
- Sync waves enforce ordering
- KRO before RGDs, RGDs before instances, infrastructure before workloads
- Health checks prevent premature progression
- Automated rollback on failures

### 5.5 Multi-Tenancy Ready
- Cluster labels enable targeting
- Spoke isolation via namespaces
- Hub manages cross-cluster concerns
- Per-cluster IAM roles

---

## 6. Operational Procedures

### 6.1 Adding a New Spoke
1. Create directory: `argocd/spokes/spoke2/`
2. Copy structure from `spoke1`:
   ```bash
   cp -r argocd/spokes/spoke1 argocd/spokes/spoke2
   ```
3. Update configs:
   - `infrastructure/values.yaml`: Set account ID, region, VPC CIDR
   - `addons/enablement.yaml`: Enable/disable addons
   - `addons/values.yaml`: Update IAM role ARNs for spoke2
   - `sample.gen3.url.org/values/values.yaml`: Update Gen3 config
4. Commit and push to git:
   ```bash
   git add argocd/spokes/spoke2
   git commit -m "Add spoke2 cluster configuration"
   git push
   ```
5. ArgoCD auto-discovers and deploys within minutes

### 6.2 Enabling a New Addon
1. Add to catalog: `argocd/hub/addons/catalog.yaml`
   ```yaml
   - addon: new-addon
     repoURL: https://charts.example.com
     revision: 1.0.0
     chartPath: new-addon
   ```
2. Enable in hub: `argocd/hub/addons/enablement.yaml`
   ```yaml
   new-addon:
     enabled: true
   ```
3. Add values: `argocd/hub/addons/values.yaml`
   ```yaml
   new-addon:
     namespace: new-addon-system
     config:
       key: value
   ```
4. Optionally enable in spokes: `argocd/spokes/*/addons/enablement.yaml`
5. Commit and push; ArgoCD syncs automatically

### 6.3 Updating Controller Versions
1. Edit catalog: Update `revision` field
   ```yaml
   - addon: ec2
     repoURL: oci://public.ecr.aws/aws-controllers-k8s/ec2-chart
     revision: v1.8.0  # Updated from v1.7.0
     chartPath: ec2-chart
   ```
2. Commit and push
3. ArgoCD detects and upgrades controller

### 6.4 Troubleshooting

**Check Sync Waves**:
```bash
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,WAVE:.metadata.annotations."argocd\.argoproj\.io/sync-wave",HEALTH:.status.health.status,SYNC:.status.sync.status
```

**Validate Labels**:
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.fleet_member}{"\n"}{end}'
```

**Review Generators**:
- Use ArgoCD UI → ApplicationSets → <appset-name> → "Generated Applications"
- Check for missing apps or unexpected entries

**Check ApplicationSet Controller Logs**:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=100
```

**Common Issues**:
- **KRO not available**: Check Wave 0 addons synced successfully
- **RGD not found**: Ensure graphs (Wave 1) completed before graph-instances (Wave 2)
- **Missing cluster**: Verify cluster secret has correct labels
- **Generator errors**: Check git paths and file patterns in ApplicationSets

---

## 7. Security Considerations

### 7.1 IAM Roles
- Each ACK controller has dedicated IAM role
- IRSA (IAM Roles for Service Accounts) for authentication
- Role ARNs stored in values files, templated into Helm charts
- Least privilege: Roles have minimal permissions per controller

### 7.2 Secret Management
- External Secrets Operator for AWS Secrets Manager integration
- Secrets synced from Secrets Manager to Kubernetes
- No secrets in Git (IAM role ARNs are not secrets, just identifiers)
- Hub stores ArgoCD cluster secrets in AWS Secrets Manager

### 7.3 Network Policies
- Kyverno policies enforce security standards
- Namespace isolation between workloads
- Hub-spoke communication via ArgoCD API server (TLS)
- ACK controllers use VPC endpoints for AWS API calls

### 7.4 RBAC
- ArgoCD projects for multi-tenancy
- Cluster-scoped vs namespace-scoped deployments
- Service account permissions managed by Kyverno policies

---

## 8. Validation and Testing

### 8.1 Pre-Deployment Checks
- **Validate YAML syntax**:
  ```bash
  kubectl apply --dry-run=client -f argocd/bootstrap/
  ```
- **Lint Helm charts** (if creating custom charts):
  ```bash
  helm lint <chart-path>
  ```
- **Test kustomizations**:
  ```bash
  kustomize build argocd/spokes/spoke1/infrastructure/
  ```
- **Verify file paths**:
  ```bash
  ls argocd/shared/graphs/aws/*.yaml
  ls argocd/spokes/*/infrastructure/kustomization.yaml
  ```

### 8.2 Post-Deployment Verification

**Step 1: Check ApplicationSets**:
```bash
kubectl get applicationsets -n argocd
# Expected: addons, graphs, graph-instances, gen3-instances
```

**Step 2: Check Generated Applications**:
```bash
kubectl get applications -n argocd
# Expected: hub-kro, hub-ec2, spoke1-ec2, spoke1-graph-instances, etc.
```

**Step 3: Check Sync Status**:
- ArgoCD UI → Applications → Filter by Health/Sync
- All should be "Healthy" and "Synced"

**Step 4: Verify Controllers**:
```bash
kubectl get pods -n ack-system
kubectl get pods -n kro-system
kubectl get pods -n external-secrets-system
```

**Step 5: Verify RGDs**:
```bash
kubectl get rgd
# Expected: ekscluster.kro.run, vpc.kro.run, efs.kro.run, etc.
```

**Step 6: Verify Instances**:
```bash
kubectl get ekscluster
# Expected: spoke1-cluster, spoke2-cluster, etc.
```

**Step 7: Verify AWS Resources** (via ACK):
```bash
kubectl get clusters.eks -A  # ACK EKS clusters
kubectl get vpcs.ec2 -A      # ACK VPCs
```

### 8.3 Health Metrics
- **ArgoCD Application Health**: Healthy/Progressing/Degraded/Missing
- **Sync Status**: Synced/OutOfSync
- **Controller Pod Status**: Running
- **Resource Creation Status**: AWS resources via ACK CRs
- **KRO Instance Status**: Check `.status` on EksCluster CRs

---

## 9. Benefits Summary

✅ **Complete Automation**: Zero manual deployment steps  
✅ **Ordered Deployment**: Sync waves prevent dependency failures  
✅ **Scalable**: Add spokes/addons via git commits  
✅ **Consistent**: Standardized config structure  
✅ **Maintainable**: DRY principles, shared bases  
✅ **Observable**: ArgoCD UI shows full deployment state  
✅ **Recoverable**: GitOps enables rollback via git revert  
✅ **Secure**: IRSA, secret management, network policies  
✅ **Testable**: Dry-run, lint, kustomize build before deploy  
✅ **Multi-Cluster**: Hub-spoke topology, centralized control  

---

## 10. Implementation Checklist

- [x] Move ApplicationSets to `argocd/bootstrap/`
- [x] Configure sync waves (0-3)
- [x] Update bootstrap ApplicationSet for recursion
- [x] Create addons catalog with all 18 controllers
- [x] Configure hub enablement/values
- [x] Configure spoke enablement/values
- [x] Create shared RGDs in `shared/graphs/aws/`
- [x] Create shared instances with kustomizations
- [x] Create spoke infrastructure overlays
- [x] Create Gen3 instance templates
- [ ] Populate IAM role ARNs in values files (environment-specific)
- [ ] Test deployment on staging environment
- [ ] Document spoke onboarding process (SOP)
- [ ] Create runbooks for common operations
- [ ] Set up monitoring/alerting for ApplicationSet health
- [ ] Train team on GitOps workflow

---

## 11. Next Steps

1. **Validate IAM Roles**: Ensure all role ARNs in `values.yaml` exist in AWS
2. **Test Bootstrap**: Run `terraform apply` in staging
3. **Monitor Deployment**: Watch ArgoCD UI for sync waves completing
4. **Verify Infrastructure**: Check AWS console for created resources
5. **Deploy Test Workload**: Add a test Gen3 instance to spoke1
6. **Document Lessons Learned**: Update this proposal with real-world findings
7. **Production Deployment**: Repeat process in prod environment

---

**End of Comprehensive Deployment Proposal**

---

## Appendix A: Full Controller List

### ACK Controllers (15)
1. cloudtrail
2. cloudwatchlogs
3. ec2
4. efs
5. eks
6. iam
7. kms
8. opensearchservice
9. rds
10. route53
11. s3
12. secretsmanager
13. sns
14. sqs
15. wafv2

### Platform Components (3)
16. external-secrets
17. kube-state-metrics
18. kro (CRITICAL for RGDs)

### Optional/Future (in enablement but not required)
- kyverno
- kyverno-policies
- metrics-server
- cert-manager
- external-dns

---

## Appendix B: Sync Wave Summary

| Wave | ApplicationSet      | Target Cluster | Purpose                          | Dependencies      |
|------|---------------------|----------------|----------------------------------|-------------------|
| 0    | addons              | hub + spokes   | Controllers, KRO, platform tools | None (first)      |
| 1    | graphs              | hub only       | ResourceGraphDefinitions         | KRO (Wave 0)      |
| 2    | graph-instances     | hub only       | Infrastructure instances         | RGDs (Wave 1)     |
| 3    | gen3-instances      | spokes only    | Gen3 workload apps               | Infra (Wave 2)    |

---

## Appendix C: File Tree
```
argocd/
├── bootstrap/
│   ├── addons.yaml              # Wave 0
│   ├── graphs.yaml              # Wave 1
│   ├── graph-instances.yaml     # Wave 2
│   └── gen3-instances.yaml      # Wave 3
├── hub/
│   └── addons/
│       ├── catalog.yaml
│       ├── enablement.yaml
│       └── values.yaml
├── shared/
│   ├── graphs/
│   │   └── aws/
│   │       ├── efs-rgd.yaml
│   │       ├── eks-cluster-rgd.yaml
│   │       ├── iam-addons-rgd.yaml
│   │       ├── iam-roles-rgd.yaml
│   │       └── vpc-network-rgd.yaml
│   └── instances/
│       ├── eks-cluster-instance.yaml
│       └── kustomization.yaml
└── spokes/
    └── spoke1/
        ├── addons/
        │   ├── catalog.yaml
        │   ├── enablement.yaml
        │   └── values.yaml
        ├── infrastructure/
        │   ├── kustomization.yaml
        │   └── values.yaml
        └── sample.gen3.url.org/
            ├── templates/
            │   └── app.yaml
            └── values/
                └── values.yaml
```
