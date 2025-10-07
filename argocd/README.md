# ArgoCD GitOps Configuration

> GitOps-based application deployment using ArgoCD for gen3-kro

## Overview

This directory contains all ArgoCD ApplicationSets, applications, Helm charts, and KRO resource graph definitions for the gen3-kro platform. ArgoCD provides declarative, GitOps continuous delivery for Kubernetes.

## Architecture

### Directory Structure

```
argocd/
├── addons/                 # Infrastructure components (sync-wave: -1)
│   ├── bootstrap/
│   │   └── default/
│   └── default/
│       └── addons/
│
├── apps/                   # Application workloads (sync-wave: 3)
│   ├── backend/
│   │   ├── carts/
│   │   ├── catalog/
│   │   ├── checkout/
│   │   ├── orders/
│   │   └── rabbitmq/
│   └── frontend/
│       ├── assets/
│       └── ui/
│
├── charts/                 # Helm charts
│   ├── application-sets/
│   ├── kro/
│   │   ├── instances/
│   │   └── resource-groups/
│   ├── kro-clusters/
│   ├── multi-acct/
│   ├── pod-identity/
│   └── storageclass-resources/
│
├── fleet/                  # KRO resource graph definitions (sync-wave: 0)
│   ├── bootstrap/
│   │   ├── addons.yaml
│   │   ├── argoprojects-appset.yaml
│   │   ├── clusters.yaml
│   │   ├── namespaces-appset.yaml
│   │   ├── web-store-backend-appset.yaml
│   │   └── web-store-frontend-appset.yaml
│   └── kro-values/
│       └── tenants/
│
└── platform/               # Platform services (sync-wave: 1)
    ├── bootstrap/
    ├── charts/
    └── teams/
```

### Sync Waves

Applications are deployed in order using ArgoCD sync waves:

| Wave | Component | Description | Examples |
|------|-----------|-------------|----------|
| -1   | Addons    | Infrastructure components | Metrics server, cluster autoscaler |
| 0    | Fleet     | KRO resource graphs | RGDs, tenant configs |
| 1    | Platform  | Platform services | Observability, security |
| 3    | Apps      | Application workloads | Web store, APIs |

**Sync Wave Annotation**:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
```

## ApplicationSets

### Bootstrap ApplicationSets

Located in `fleet/bootstrap/`:

#### 1. addons.yaml
**Purpose**: Deploy core infrastructure components

**Sync Wave**: `-1` (first to deploy)

**Pattern**: List generator with multiple addons
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: addons
spec:
  generators:
    - list:
        elements:
          - name: metrics-server
          - name: cluster-autoscaler
  template:
    metadata:
      name: '{{name}}'
    spec:
      project: default
      source:
        repoURL: '{{metadata.annotations.fleet_repo_url}}'
        targetRevision: main
        path: 'argocd/addons/{{name}}'
```

#### 2. clusters.yaml
**Purpose**: Deploy KRO resource graph definitions

**Sync Wave**: `0` (after addons)

**Pattern**: Git directory generator
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kro-clusters
spec:
  generators:
    - git:
        repoURL: https://github.com/indiana-university/gen3-kro
        revision: main
        directories:
          - path: argocd/fleet/kro-values/*
```

#### 3. web-store-backend-appset.yaml
**Purpose**: Deploy backend microservices

**Sync Wave**: `3` (application workloads)

**Pattern**: Matrix generator (environments × tenants)

#### 4. web-store-frontend-appset.yaml
**Purpose**: Deploy frontend applications

**Sync Wave**: `3` (application workloads)

### Generator Patterns

#### List Generator
Explicitly define applications:
```yaml
generators:
  - list:
      elements:
        - name: app1
          namespace: default
        - name: app2
          namespace: production
```

#### Git Directory Generator
Auto-discover from Git repository:
```yaml
generators:
  - git:
      repoURL: https://github.com/indiana-university/gen3-kro
      revision: main
      directories:
        - path: argocd/apps/*
```

#### Matrix Generator
Combine multiple generators:
```yaml
generators:
  - matrix:
      generators:
        - list:  # Environments
            elements:
              - env: dev
              - env: staging
              - env: prod
        - list:  # Tenants
            elements:
              - tenant: tenant1
              - tenant: tenant2
```

## Value File Layering

ArgoCD supports layered value files with **last-wins** semantics:

```yaml
spec:
  source:
    helm:
      valueFiles:
        - '$values/kro-values/default/base-values.yaml'      # Base layer
        - '$values/kro-values/tenants/{{tenant}}/values.yaml' # Tenant overrides
        - '$values/kro-values/envs/{{env}}/values.yaml'      # Environment overrides
```

**Order**: Base → Tenant → Environment (last wins)

### Example: Multi-Tenant Configuration

**Base Values** (`kro-values/default/base-values.yaml`):
```yaml
replicaCount: 1
resources:
  limits:
    cpu: 100m
    memory: 128Mi
```

**Tenant Override** (`kro-values/tenants/tenant1/values.yaml`):
```yaml
replicaCount: 3  # Override for high-traffic tenant
domain: tenant1.example.com
```

**Environment Override** (`kro-values/envs/prod/values.yaml`):
```yaml
resources:
  limits:
    cpu: 500m    # Override for production
    memory: 512Mi
```

**Result**: Production tenant1 gets 3 replicas with 500m CPU and 512Mi memory

## KRO Resource Graph Definitions

### What is KRO?

KRO (Kubernetes Resource Operator) allows you to define complex resource dependencies as declarative graphs.

### RGD Structure

**Resource Graph Definition** (RGD):
```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: eks-cluster
  namespace: kro
spec:
  schema:
    apiVersion: v1alpha1
    kind: EKSCluster
    spec:
      region: string
      version: string
      nodeGroups: array
  resources:
    - id: vpc
      template:
        apiVersion: ec2.services.k8s.aws/v1alpha1
        kind: VPC
        spec:
          cidrBlock: "10.0.0.0/16"

    - id: cluster
      template:
        apiVersion: eks.services.k8s.aws/v1alpha1
        kind: Cluster
        spec:
          name: ${schema.spec.clusterName}
          version: ${schema.spec.version}
          resourcesVPCConfig:
            vpcID: ${vpc.status.vpcID}
```

### Instance

**Resource Graph Instance**:
```yaml
apiVersion: kro.run/v1alpha1
kind: EKSCluster
metadata:
  name: spoke1-cluster
spec:
  region: us-east-1
  version: "1.31"
  nodeGroups:
    - name: default
      instanceType: t3.medium
      minSize: 2
      maxSize: 4
```

**Result**: KRO creates VPC, subnets, security groups, EKS cluster, and node groups

## Common Operations

### Deploy New Application

1. **Create Application Manifest**:
   ```bash
   mkdir -p argocd/apps/my-app
   vim argocd/apps/my-app/deployment.yaml
   ```

2. **Add to ApplicationSet** (or create standalone Application):
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/indiana-university/gen3-kro
       targetRevision: main
       path: argocd/apps/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

3. **Commit and Push**:
   ```bash
   git add argocd/apps/my-app/
   git commit -m "Add my-app"
   git push
   ```

4. **Verify Deployment**:
   ```bash
   # ArgoCD syncs within 3 minutes
   kubectl get applications -n argocd
   argocd app get my-app
   ```

### Update Application

1. **Edit Manifests**:
   ```bash
   vim argocd/apps/my-app/deployment.yaml
   ```

2. **Commit and Push**:
   ```bash
   git add argocd/apps/my-app/
   git commit -m "Update my-app resources"
   git push
   ```

3. **Wait for Sync** (or trigger manually):
   ```bash
   argocd app sync my-app
   ```

### Add New Tenant

1. **Create Tenant Values**:
   ```bash
   mkdir -p argocd/fleet/kro-values/tenants/tenant2
   vim argocd/fleet/kro-values/tenants/tenant2/values.yaml
   ```

2. **Commit and Push**:
   ```bash
   git add argocd/fleet/kro-values/tenants/tenant2/
   git commit -m "Add tenant2 configuration"
   git push
   ```

3. **ArgoCD Auto-Discovers**: Matrix generator creates new application

### Create Custom Helm Chart

1. **Create Chart Structure**:
   ```bash
   mkdir -p argocd/charts/my-chart
   cd argocd/charts/my-chart
   helm create .
   ```

2. **Customize Chart**:
   ```bash
   vim Chart.yaml
   vim values.yaml
   vim templates/deployment.yaml
   ```

3. **Reference in ApplicationSet**:
   ```yaml
   source:
     chart: my-chart
     repoURL: https://github.com/indiana-university/gen3-kro
     targetRevision: main
     path: argocd/charts/my-chart
   ```

## Go Template Variables

ApplicationSets support Go templating:

### Common Variables

```yaml
# From metadata labels
{{.metadata.labels.environment}}     # dev, staging, prod
{{.metadata.labels.tenant}}         # tenant1, tenant2
{{.metadata.labels.region}}         # us-east-1, us-west-2

# From metadata annotations
{{.metadata.annotations.fleet_repo_url}}  # Git repo URL

# From list generator
{{.name}}                           # Application name
{{.namespace}}                      # Target namespace

# From git generator
{{.path.basename}}                  # Directory name
{{.path.segments[0]}}              # First path segment
```

### Example Usage

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: multi-env-app
spec:
  generators:
    - list:
        elements:
          - env: dev
            replicas: 1
          - env: staging
            replicas: 2
          - env: prod
            replicas: 5
  template:
    metadata:
      name: 'app-{{env}}'
    spec:
      source:
        helm:
          parameters:
            - name: replicaCount
              value: '{{replicas}}'
            - name: environment
              value: '{{env}}'
```

## Monitoring & Troubleshooting

### Check Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Get application details
argocd app get my-app

# View application tree
argocd app tree my-app

# View sync history
argocd app history my-app
```

### Common Issues

**Issue**: Application stuck in "Progressing"
- **Cause**: Resource failing to deploy
- **Solution**: Check resource events
  ```bash
  argocd app get my-app --show-operation
  kubectl describe deployment my-app -n my-app-namespace
  ```

**Issue**: Application "OutOfSync"
- **Cause**: Git repository changed
- **Solution**: Sync application
  ```bash
  argocd app sync my-app
  ```

**Issue**: ApplicationSet not creating Applications
- **Cause**: Generator pattern mismatch
- **Solution**: Check generator output
  ```bash
  kubectl get applicationset my-appset -n argocd -o yaml
  kubectl describe applicationset my-appset -n argocd
  ```

**Issue**: Sync wave order incorrect
- **Cause**: Missing or wrong annotation
- **Solution**: Check sync-wave annotations
  ```bash
  kubectl get applications -n argocd \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}'
  ```

### Debug Mode

```bash
# View ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# View ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# View ApplicationSet controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller
```

## Best Practices

### ✅ Do

- **Use ApplicationSets** for managing multiple similar applications
- **Use sync waves** for ordered deployment
- **Enable auto-sync** for automatic GitOps
- **Use value file layering** for multi-tenant/multi-environment
- **Add health checks** for custom resources
- **Use namespaces** for isolation
- **Tag commits** for traceability

### ❌ Don't

- **DON'T apply resources directly** (`kubectl apply`) - use Git
- **DON'T skip sync waves** - respect dependencies
- **DON'T hardcode values** - use value files
- **DON'T delete ArgoCD finalizers** manually
- **DON'T bypass ArgoCD** for application updates

## Security

- **RBAC**: Role-based access control for ArgoCD
- **SSO**: Integration with identity providers
- **Git Authentication**: GitHub App private key
- **Secrets**: External Secrets Operator for sensitive data
- **Network Policies**: Restrict pod-to-pod communication

## Performance

- **Sync Interval**: 3 minutes (default)
- **Parallel Syncs**: 5 (configurable)
- **Resource Tracking**: Git commit SHA
- **Cache**: Redis for repository caching

## Related Documentation

- [Main README](../README.md)
- [Terraform Documentation](../terraform/README.md)
- [ArgoCD Troubleshooting](../docs/argocd/troubleshooting.md)
- [ApplicationSet Patterns](../docs/argocd/applicationsets.md)

---

**Last Updated**: October 7, 2025
**Maintained By**: Indiana University
