# Spoke Application Hierarchy

Brief explanation of the three ArgoCD Applications involved in spoke deployment.

## Application Flow

```
fleet-workloads (ApplicationSet on CSOC)
  └─ workloads-spoke1-spoke1-dev (Application on CSOC)
       ├─ spoke1-cluster-level-resources (Application on CSOC → deploys to spoke)
       └─ spoke1-gen3 (Application on CSOC → deploys to spoke)
```

## What Each Application Does

### 1. `workloads-spoke1-spoke1-dev` — Parent (Synced/Healthy)

- **Created by**: `fleet-workloads` ApplicationSet in [cluster-fleet.yaml](../argocd/bootstrap/cluster-fleet.yaml)
- **Source**: `argocd/charts/workloads/` Helm chart + `argocd/cluster-fleet/spoke1/workload.yaml` values
- **Destination**: CSOC cluster (itself) — because it renders ArgoCD Application CRDs that must exist where ArgoCD runs
- **Purpose**: Reads workload.yaml and renders child ArgoCD Application resources. It does NOT deploy to the spoke directly. It creates the Application CRDs below.

### 2. `spoke1-cluster-level-resources` — Cluster Infrastructure (OutOfSync)

- **Created by**: The workloads chart's `clusterResources` section
- **Source**: Helm chart for cluster-wide infrastructure (external-secrets, cert-manager, etc.)
- **Destination**: spoke1-dev cluster (via ArgoCD cluster name)
- **Purpose**: Deploys cluster-level infrastructure prerequisites to the spoke before Gen3 services arrive
- **Current Issue**: Was pointed at gen3-helm's `cluster-level-resources` app-of-apps chart, which renders more ArgoCD Application CRDs. The spoke doesn't have ArgoCD CRDs, so it fails. **Fix**: Point directly at the external-secrets Helm chart instead of the app-of-apps wrapper.

### 3. `spoke1-gen3` — Gen3 Services (OutOfSync/Missing)

- **Created by**: The workloads chart's `workloads` section
- **Source**: gen3-helm `helm/gen3` umbrella chart
- **Destination**: spoke1-dev cluster (via ArgoCD cluster name)
- **Purpose**: Deploys Gen3 services (indexd, fence, sheepdog, peregrine, arborist, metadata) with database-creation Jobs targeting the external Aurora cluster
- **Current Issue**: Previously-completed db-create Jobs (arborist-dbcreate, fence-dbcreate, etc.) are immutable K8s resources. ArgoCD can't replace them. **Fix**: Delete completed Jobs on the spoke, then re-sync.

## Key Architecture Insight

All three Applications live on the CSOC cluster (where ArgoCD runs). The spoke cluster has NO ArgoCD installation. ArgoCD on the CSOC manages the spoke remotely via the cluster secret created by the KRO ResourceGraphDefinition.

This means:
- Application CRDs must always be created on the CSOC
- The `destination.name` field points child apps at the spoke cluster
- App-of-apps charts that render more Application CRDs can only target the CSOC, never the spoke
- For spoke cluster-level resources, deploy Helm charts **directly** (not through an app-of-apps wrapper)
