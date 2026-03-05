# Spoke Application Hierarchy

How ArgoCD deploys Gen3 services to spoke clusters, matching the
[gen3-gitops](https://github.com/uc-cdis/gen3-gitops) deployment pattern
adapted for our RGD/KRO method.

## Application Flow (flat — 2 levels)

```
fleet-cluster-resources (ApplicationSet on CSOC)
  └─ spoke1-cluster-resources  (Application → deploys to spoke)

fleet-gen3 (ApplicationSet on CSOC)
  └─ spoke1-gen3               (Application → deploys to spoke)
```

No intermediate chart renders child Application CRDs. Each ApplicationSet
creates its Application directly.

## Comparison with gen3-gitops

| Concept | gen3-gitops / gen3-terraform | gen3-kro (this repo) |
|---------|------------------------------|----------------------|
| Cluster resources | `cluster-app.tftpl` → one Application per cluster | `fleet-cluster-resources` ApplicationSet → one Application per spoke |
| Gen3 services | `app.tftpl` → one Application per environment | `fleet-gen3` ApplicationSet → one Application per spoke |
| Values (cluster) | `<cluster>/cluster-values/cluster-values.yaml` | `cluster-fleet/<spoke>/cluster-resources.yaml` |
| Values (app) | `<cluster>/<hostname>/values/values.yaml` | `cluster-fleet/<spoke>/apps.yaml` |
| Infrastructure | `<cluster>/cluster-values/` (one per cluster) | `cluster-fleet/<spoke>/infrastructure.yaml` (KRO instances) |

## File Layout

```
argocd/
├── bootstrap/
│   ├── fleet-infra-instances.yaml    ← KRO infrastructure instances AppSet (wave 30)
│   ├── fleet-cluster-resources.yaml  ← Spoke cluster-level infra AppSet (wave 40)
│   └── fleet-gen3.yaml               ← Gen3 apps on spoke clusters AppSet (wave 50)
├── charts/
│   └── cluster-resources/          ← Umbrella chart (external-secrets dependency)
│       ├── Chart.yaml
│       └── values.yaml
└── cluster-fleet/
    ├── spoke1/
    │   ├── infrastructure.yaml     ← KRO instances (EKS, Aurora, VPC, etc.)
    │   ├── cluster-resources.yaml  ← Cluster-wide infra (external-secrets)
    │   └── apps.yaml               ← Gen3 service values (indexd, fence, etc.)
    └── spoke2/
        ├── infrastructure.yaml
        ├── cluster-resources.yaml
        └── apps.yaml
```

## What Each Application Does

### 1. `spoke1-cluster-resources` — Cluster Infrastructure

- **Created by**: `fleet-cluster-resources` ApplicationSet
- **Source**: `argocd/charts/cluster-resources/` umbrella chart + `cluster-fleet/spoke1/cluster-resources.yaml` values
- **Destination**: spoke cluster directly (via ArgoCD cluster name)
- **Purpose**: Deploys cluster-wide infrastructure prerequisites (external-secrets operator, future: cert-manager, karpenter nodes, etc.)
- **One per cluster**: Shared across all namespaces/environments on the spoke

### 2. `spoke1-gen3` — Gen3 Services

- **Created by**: `fleet-gen3` ApplicationSet
- **Source**: gen3-helm `helm/gen3` umbrella chart + `cluster-fleet/spoke1/apps.yaml` values
- **Destination**: spoke cluster directly (via ArgoCD cluster name)
- **Purpose**: Deploys Gen3 services (indexd, fence, sheepdog, etc.) with database-creation Jobs targeting the external Aurora cluster
- **One per environment**: Each namespace/hostname gets its own Application
- **Infrastructure injection**: Aurora endpoint, username, and database name are injected as Helm parameters from the argoCDClusterSecret annotations

## Key Architecture Points

- All Applications live on the CSOC cluster (where ArgoCD runs). The spoke has NO ArgoCD.
- `destination.name` points each Application at the spoke cluster via the cluster secret.
- Infrastructure outputs (Aurora endpoint, etc.) flow from KRO → argoCDClusterSecret annotations → ApplicationSet parameters → Helm values.
- DB passwords stay in AWS Secrets Manager — consumed on the spoke via ExternalSecrets.
- The `cluster-resources` umbrella chart deploys Helm dependencies directly (NOT gen3-helm's `cluster-level-resources` app-of-apps, which renders ArgoCD Application CRDs that don't exist on the spoke).

