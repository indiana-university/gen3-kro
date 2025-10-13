# Comprehensive Proposal for ArgoCD Bootstrap Deployment

## Overview
This proposal outlines how the bootstrap process should deploy all apps, charts, and values in the `argocd/` folder. The bootstrap ApplicationSet deploys ApplicationSets from `argocd/bootstrap/` to the hub cluster, which then deploy the remaining components hierarchically.

## Current State Analysis
- **Bootstrap ApplicationSet** (`terraform/modules/root/applicationsets.yaml`): Deploys `argocd/bootstrap/` to the hub's `argocd` namespace. Recursion is enabled to deploy all ApplicationSets.
- **ApplicationSets in `argocd/bootstrap/`**:
  - `addons.yaml`: Deploys addons (charts) to hub and spoke clusters based on enablement configs.
  - `gen3-instances.yaml`: Deploys Gen3 instance apps (e.g., `sample.gen3.url.org/`) from `argocd/spokes/*/` to spoke clusters.
  - `graphs.yaml`: Deploys kind objects in `argocd/shared/graphs/` to the hub cluster.
  - `graph-instances.yaml`: Deploys `argocd/shared/graphs/instances/` to spoke clusters using kustomize with overlays from `argocd/spokes/*/` and `argocd/shared/graphs/instances/`.

## Proposed Deployment Structure
The bootstrap deploys ApplicationSets to the hub, which fan out to deploy components based on cluster selectors and sync waves.

### 1. **Bootstrap ApplicationSet Updates**
- Enable `directory.recurse: true` in `terraform/modules/root/applicationsets.yaml` to deploy all YAMLs in `bootstrap/`.

### 2. **ApplicationSets Details**
- **addons.yaml**: Deploys charts to clusters based on `argocd/hub/addons/` and `argocd/spokes/*/addons/` configs.
- **gen3-instances.yaml**: Deploys Gen3 apps to spokes (e.g., `argocd/spokes/*/sample.gen3.url.org/`).
- **graphs.yaml**: Deploys `argocd/shared/graphs/` (RGDs) to hub.
- **graph-instances.yaml**: Deploys instances to spokes with kustomize overlays.

### 3. **Deployment Flow**
1. **Bootstrap (Sync Wave 0)**: Deploys ApplicationSets to hub.
2. **Graphs (Sync Wave 0)**: Deploys RGDs to hub.
3. **Addons (Sync Wave 1)**: Deploys charts to eligible clusters.
4. **Graph-Instances (Sync Wave 2)**: Deploys instances to spokes.
5. **Gen3-Instances (Sync Wave 3)**: Deploys Gen3 apps to spokes.

## Implementation Steps
1. Files are already in `argocd/bootstrap/` and modified as per changes.
2. Update `terraform/modules/root/applicationsets.yaml` for recursion.
3. Test deployment.

## Benefits and Mitigations
- Ensures complete deployment.
- Handles dependencies with sync waves.
- Assumes kustomizations include necessary bases.</content>
<parameter name="filePath">/workspaces/gen3-kro/argocd/bootstrap/README.md