# Karpenter and ArgoCD Topology Report

**Date:** 2026-05-02
**Scope:** `cluster-level-resources`, KRO `AwsGen3ClusterResources1`, and Karpenter node configuration rendering

## Executive Summary

The current `cluster-level-resources` deployment path is mixing two different ArgoCD topologies:

1. **Spoke ArgoCD model:** CSOC ArgoCD pushes the `cluster-level-resources` app-of-apps chart to the spoke, and a spoke-local ArgoCD controller reconciles the child Applications.
2. **CSOC-only model:** CSOC ArgoCD is the only controller, so all child Applications must be created in CSOC and target the spoke by `destination.server`.

The recent Karpenter modifications tried to support the CSOC-only model by converting Karpenter node configuration resources into per-file child ArgoCD Applications when `karpenter.configuration.enabled=true`. That change addresses a real problem in the CSOC-only topology, but it does so in the wrong layer. It makes the Karpenter templates responsible for deployment topology instead of keeping topology decisions in the ArgoCD Application orchestration layer.

The better fix is to make the topology explicit and consistent. Direct Kubernetes manifests such as `EC2NodeClass` and `NodePool` should remain direct manifests when the parent Application targets the spoke. If CSOC-only is required, those direct manifests should be split into a separate spoke-targeting chart or Application, not wrapped ad hoc inside each Karpenter node-config template.

## Current State

The KRO ResourceGraphDefinition at:

- `argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml`

creates a `clusterResourcesApp` ArgoCD Application for the Gen3 `cluster-level-resources` chart.

The current RGD behavior targets the parent Application to the registered spoke cluster:

```yaml
destination:
  name: ${schema.spec.name}-spoke
  namespace: ${schema.spec.argoCDNamespace}
```

That is the spoke-targeting model. In that model, raw Kubernetes manifests rendered by the chart are applied to the spoke cluster, because the parent Application itself targets the spoke.

However, comments and recent changes also refer to `destinationServer`, which belongs to the CSOC-only model. In that model, the parent chart should render child `Application` objects into CSOC ArgoCD, and each child Application should target the spoke via:

```yaml
destination:
  server: {{ .Values.destinationServer | default "https://kubernetes.default.svc" | quote }}
```

Those two models are mutually different. The current code has pieces of both.

## Why Karpenter Is Special

Most `cluster-level-resources` templates render ArgoCD `Application` objects. For example:

- `templates/karpenter.yaml`
- `templates/karpenter-crds.yaml`
- `templates/alb-controller.yaml`
- `templates/external-secrets.yaml`

For those templates, adding a configurable `destination.server` is appropriate. They are already ArgoCD Applications, so the only question is which cluster the child Application targets.

The Karpenter node configuration files are different:

- `templates/karpenter-config-resources-default.yaml`
- `templates/karpenter-config-resources-gpu.yaml`
- `templates/karpenter-config-resources-jupyter.yaml`
- `templates/karpenter-config-resources-secondary.yaml`
- `templates/karpenter-config-resources-workflow.yaml`

These files normally render direct Kubernetes resources:

- `EC2NodeClass`
- `NodePool`

Those resources do not have an ArgoCD `destination.server`. They are applied to whichever cluster the parent Application targets.

That means:

- If the parent Application targets the spoke, direct Karpenter manifests are correct.
- If the parent Application renders into CSOC, direct Karpenter manifests are incorrect because they would be applied to CSOC, not the spoke.

The recent per-file `if/else` conversion tries to solve the second case by turning each node config into another ArgoCD Application. That works around the problem, but it spreads deployment topology decisions across multiple Karpenter files.

## Problem With The Current Modification

The current modification is not ideal for four reasons.

### 1. It mixes topology with resource definition

Karpenter node config templates should define Karpenter resources. They should not also decide whether this deployment is CSOC-only or spoke-local.

That decision belongs at the ArgoCD orchestration layer:

- parent Application destination
- child Application destination
- chart split or Application split for direct manifests

### 2. It creates inconsistent behavior

Some templates render child ArgoCD Applications.

Some templates render raw Kubernetes resources.

Some Karpenter templates now switch between both depending on `karpenter.configuration.enabled`.

That makes the rendered output hard to reason about and easy to break during future Gen3 chart updates.

### 3. It introduces or exposes Helm bugs

The inline Karpenter branch currently has invalid Helm syntax:

```gotemplate
{{- if not index .Values "karpenter-crds" "useAlias" }}
```

This should be:

```gotemplate
{{- if not (index .Values "karpenter-crds" "useAlias") }}
```

There is also a likely typo in the default node config:

```gotemplate
{{- if not index .Values "karpenter-crds" "usaAlias" }}
```

The chart values define `useAlias`, not `usaAlias`.

### 4. It does not fully solve the Application destination problem

Several real `kind: Application` templates still appear to hard-code:

```yaml
server: https://kubernetes.default.svc
```

Examples observed in the reference chart include:

- `templates/argo-workflow.yaml`
- `templates/argo-events.yaml`
- `templates/grafana-alloy.yaml`
- `templates/kube-state-metrics.yaml`

If the chosen model is CSOC-only, all real Application templates need a consistent `destinationServer` pattern. Fixing only Karpenter does not make the chart CSOC-ready.

## Deployment Models

### Option A: Spoke ArgoCD

In this model, the spoke cluster runs ArgoCD.

The CSOC creates or syncs the parent `cluster-level-resources` Application to the spoke. The spoke-local ArgoCD controller then reconciles the child Applications and any direct Kubernetes manifests.

This model allows the Karpenter node config files to remain direct manifests.

Advantages:

- Matches the original Gen3 chart assumption.
- Raw Karpenter resources work without wrapping.
- No fork-specific topology logic inside Karpenter templates.
- The spoke can self-heal cluster add-ons if CSOC is unavailable.

Disadvantages:

- Requires ArgoCD on every spoke.
- Adds operational overhead per spoke.
- Requires bootstrapping spoke ArgoCD before cluster add-ons reconcile.

### Option B: CSOC-Only ArgoCD

In this model, CSOC ArgoCD is the only ArgoCD controller.

The parent Application should render child Application CRs into CSOC ArgoCD. Each child Application must target the spoke with `destinationServer`.

This model cannot safely mix direct Kubernetes manifests into the same parent chart unless the parent Application itself targets the spoke. Direct manifests need a separate handling path.

Advantages:

- Single ArgoCD control plane for the whole fleet.
- No per-spoke ArgoCD installation.
- Easier fleet-wide add-on upgrades.

Disadvantages:

- Requires chart changes.
- Direct manifests such as Karpenter `EC2NodeClass` and `NodePool` need a clean split.
- CSOC availability becomes more important for add-on self-healing.

## Recommended Fix

I would choose one topology explicitly, then simplify the chart around that choice.

### Recommended direction: keep Karpenter resources direct

My preferred fix is:

1. Revert the Karpenter node-config Application conversion.
2. Keep `EC2NodeClass` and `NodePool` as direct Kubernetes manifests.
3. Make the parent ArgoCD Application responsible for applying those direct manifests to the correct cluster.
4. Fix only real `kind: Application` templates to use `destinationServer`.
5. Update `07-clusterresources1-rg.yaml` comments and behavior so it clearly documents the selected topology.

This keeps Karpenter resource definition separate from ArgoCD deployment topology.

### If CSOC-only is required

If the final decision is that CSOC ArgoCD must be the only controller, I would not keep the current per-file Karpenter wrappers.

Instead, I would split direct Kubernetes manifests into their own spoke-targeting unit. Possible implementations:

1. Create a small separate chart for Karpenter node configs and have KRO create an ArgoCD Application that targets the spoke.
2. Move Karpenter node configs into a dedicated path in the values/configuration repo and have one explicit Application manage that path.
3. Split the upstream `cluster-level-resources` app-of-apps chart into:
   - child Application generator chart, rendered into CSOC
   - direct-manifest chart, synced to the spoke

The important point is that the split should happen once at the orchestration boundary, not repeatedly inside every Karpenter node config file.

## Immediate Cleanup Checklist

1. Revert the Karpenter node-config Application conversion.

   Restore these templates to render only Karpenter resources:

   - `karpenter-config-resources-default.yaml`
   - `karpenter-config-resources-gpu.yaml`
   - `karpenter-config-resources-jupyter.yaml`
   - `karpenter-config-resources-secondary.yaml`
   - `karpenter-config-resources-workflow.yaml`

2. Fix Helm syntax in the inline Karpenter templates.

   Replace:

   ```gotemplate
   {{- if not index .Values "karpenter-crds" "useAlias" }}
   ```

   with:

   ```gotemplate
   {{- if not (index .Values "karpenter-crds" "useAlias") }}
   ```

3. Fix the likely typo.

   Replace:

   ```gotemplate
   "usaAlias"
   ```

   with:

   ```gotemplate
   "useAlias"
   ```

4. Make real Application templates consistently use `destinationServer`.

   Search for:

   ```yaml
   server: https://kubernetes.default.svc
   ```

   and update real ArgoCD Application templates to:

   ```gotemplate
   server: {{ .Values.destinationServer | default "https://kubernetes.default.svc" | quote }}
   ```

5. Fix or remove conflicting comments in `07-clusterresources1-rg.yaml`.

   The file should state one of these clearly:

   - parent app targets the spoke and raw manifests are applied there
   - parent app targets CSOC and all spoke workloads are delivered through child Applications

6. Add render checks.

   At minimum:

   ```bash
   helm template cluster-level-resources references/gen3-build/helm/cluster-level-resources \
     -f argocd/fleet/spoke1/cluster-level-resources/cluster-values.yaml \
     --set cluster=gen3 \
     --set project=gen3 \
     --set accountNumber=123456789012 \
     --set eksClusterEndpoint=https://example.eks.amazonaws.com \
     --kube-version 1.33.0
   ```

   Also test with:

   ```bash
   --set destinationServer=https://spoke.example.com
   ```

## Conclusion

The Karpenter change is understandable, but it is solving an ArgoCD topology problem inside Karpenter resource templates.

The clean fix is to make the deployment model explicit:

- If using spoke ArgoCD or a parent Application that targets the spoke, keep Karpenter node configs as direct manifests.
- If using CSOC-only ArgoCD, split direct Karpenter manifests into a single spoke-targeting chart or Application.

In both cases, real ArgoCD `Application` templates should consistently support `destinationServer`, and `07-clusterresources1-rg.yaml` should document and enforce only one topology.
