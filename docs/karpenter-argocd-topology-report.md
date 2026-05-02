# Karpenter and ArgoCD Topology Report

**Date:** 2026-05-02  
**Scope:** `cluster-level-resources`, KRO `AwsGen3ClusterResources1`, and Karpenter node configuration rendering

## Executive Summary

The earlier framing of Option A and Option B was too coarse. In both options, the RGD in CSOC creates ArgoCD Applications for Gen3 and cluster-level resources, and in both options the intended Kubernetes workloads ultimately run in the spoke cluster.

The real difference is:

1. Where the ArgoCD `Application` CRs live
2. Which ArgoCD controller reconciles them

With that corrected framing:

- `Option A` means the `Application` CRs for spoke add-ons live in the spoke, and spoke ArgoCD reconciles them independently of CSOC.
- `Option B` means the `Application` CRs live in the hub, and hub ArgoCD reconciles them against the spoke remotely.

That clarification matters for Karpenter. The recent Karpenter changes were trying to solve a real problem in Option B, but they solved it by pushing deployment-topology logic down into the Karpenter node-config templates. That makes the chart harder to reason about and harder to maintain.

## Corrected Option Definitions

### Option A: Spoke ArgoCD

In Option A, ArgoCD is preinstalled into the spoke by a version2-style RGD or equivalent bootstrap path.

The CSOC-side RGD still originates the workflow, but the cluster-level resource `Application` CRs are created in the spoke, where spoke ArgoCD reconciles them locally. The workloads still land in the spoke, but management of those `Application` CRs is independent of CSOC after bootstrap.

### Option B: Hub ArgoCD managing the spoke

In Option B, version1 is used and the `Application` CRs remain in the hub.

Hub ArgoCD reconciles those `Application` objects and applies their managed resources into the spoke cluster remotely. The workloads still land in the spoke. The difference from Option A is not workload destination, but where the `Application` CRs exist and which controller owns their reconciliation lifecycle.

## Current State

The current KRO ResourceGraphDefinition:

- `argocd/charts/resource-groups/templates/07-clusterresources1-rg.yaml`

creates a parent ArgoCD `Application` for the `cluster-level-resources` chart.

Today the file is described partly as if the parent chart is a spoke-targeting app-of-apps and partly as if the child `Application` objects should live in the hub and use `destinationServer` to target the spoke. Those are different control models.

That is the actual architectural tension:

- `Option A`: child `Application` CRs should end up in the spoke and be reconciled by spoke ArgoCD.
- `Option B`: child `Application` CRs should stay in the hub and be reconciled by hub ArgoCD against the spoke.

The earlier report language incorrectly described the distinction as if Option B meant “CSOC gets the workloads.” That is not the goal. The workloads are supposed to land in the spoke in both options.

## Why Karpenter Is Special

Most `cluster-level-resources` templates already render ArgoCD `Application` objects. Examples:

- `templates/karpenter.yaml`
- `templates/karpenter-crds.yaml`
- `templates/alb-controller.yaml`
- `templates/external-secrets.yaml`

For those templates, changing `destination.server` is a natural fit for Option B because they are already Application CRs.

The Karpenter node configuration files are different:

- `templates/karpenter-config-resources-default.yaml`
- `templates/karpenter-config-resources-gpu.yaml`
- `templates/karpenter-config-resources-jupyter.yaml`
- `templates/karpenter-config-resources-secondary.yaml`
- `templates/karpenter-config-resources-workflow.yaml`

These files render direct Kubernetes resources:

- `EC2NodeClass`
- `NodePool`

Direct manifests do not carry ArgoCD destination metadata. They are applied wherever the parent chart is reconciled.

That means:

- In `Option A`, this is fine if the Karpenter direct manifests are ultimately rendered and applied in the spoke context.
- In `Option B`, this is a problem if the chart is rendered in the hub and those direct manifests are emitted there, because they would not be represented as remote-targeting `Application` CRs.

This is why Karpenter became the awkward part of the change. The issue is real, but the solution needs to be described in terms of `Application` CR placement and controller ownership, not just “spoke versus CSOC.”

## What The Recent Modification Tried To Do

The recent Karpenter modification added per-file `if/else` behavior so that, when `karpenter.configuration.enabled=true`, the Karpenter node-config templates render ArgoCD `Application` objects instead of direct manifests.

That is trying to make the Karpenter node configs compatible with Option B:

- child `Application` CRs stay in the hub
- hub ArgoCD reconciles them
- the child apps target the spoke through `destinationServer`

That is a legitimate architectural need in Option B. The concern is not that the change is irrational. The concern is that it encodes deployment mode inside the Karpenter resource templates themselves.

## Problem With The Current Karpenter Approach

### 1. It hides the real decision point

The real system decision is:

- where should the `Application` CRs live?
- which ArgoCD controller should own them?

The per-file Karpenter wrapper makes that decision look like a Karpenter-only implementation detail.

### 2. It makes one chart represent two different control models

The same chart now partially behaves like:

- a direct-manifest chart
- an app-of-apps chart

That makes troubleshooting harder because the rendering behavior changes by feature flag and by template type.

### 3. It still leaves consistency gaps

Even if Karpenter is wrapped this way, all real `kind: Application` templates still need consistent destination handling for Option B. A partial `destinationServer` rollout is not enough.

### 4. It exposed template bugs

The Karpenter files still contain invalid Helm syntax such as:

```gotemplate
{{- if not index .Values "karpenter-crds" "useAlias" }}
```

which must be:

```gotemplate
{{- if not (index .Values "karpenter-crds" "useAlias") }}
```

There is also a typo in the default node-config template:

```gotemplate
"usaAlias"
```

The value key is:

```gotemplate
"useAlias"
```

## Revised Reading Of Option A And Option B

### Option A

Option A is not simply “ArgoCD on the spoke” in the abstract. It is:

- CSOC RGD creates or bootstraps spoke ArgoCD
- the relevant `Application` CRs for cluster add-ons exist in the spoke
- spoke ArgoCD reconciles those Applications independently

Under this model, direct Karpenter manifests are conceptually acceptable because the spoke-side reconciliation context is the one that matters.

### Option B

Option B is not “CSOC gets the resources.” It is:

- the `Application` CRs live in the hub
- hub ArgoCD reconciles them
- those Applications target the spoke cluster remotely

Under this model, any direct manifests mixed into the same rendering path need special treatment, because direct manifests are not remote-targeting `Application` CRs.

## Recommendation

The report should describe the decision this way:

- Both options are spoke-targeting
- The difference is `Application` CR placement and controller ownership

For Karpenter specifically, I would still keep the caution that the current per-file wrapper approach is not the cleanest long-term shape. But the reason should be stated more precisely:

- In Option B, Karpenter direct manifests do create a real problem
- The current solution addresses that problem by moving control-plane logic into resource templates
- That may be acceptable as a tactical step, but it is not the cleanest architectural boundary

## Recommended Documentation Wording

Use this definition consistently in reports and prompts:

`Both options use an RGD in the CSOC to create ArgoCD Applications for Gen3 and cluster-level resources. In both cases, the resulting Kubernetes workloads are intended to run in the spoke cluster. The difference is where the ArgoCD Application CRs live and which ArgoCD controller reconciles them.`

Then define the options as:

- `Option A`: `Application` CRs for spoke add-ons live in the spoke, and spoke ArgoCD reconciles them.
- `Option B`: `Application` CRs stay in the hub, and hub ArgoCD reconciles them against the spoke remotely.

## Immediate Cleanup Checklist

1. Update all reports and prompts so Option A and Option B are described in terms of `Application` CR placement and controller ownership.
2. Remove wording that implies Option B sends workloads to CSOC. That is not the intended outcome.
3. Keep the Karpenter discussion, but explain that the challenge in Option B comes from direct manifests not being ArgoCD `Application` CRs.
4. Fix the Helm template bugs in the Karpenter files:
   - `not index ...` must become `not (index ...)`
   - `usaAlias` must become `useAlias`
5. Re-evaluate the Karpenter wrapper approach after the control model is documented correctly. It may still be used tactically for Option B, but it should be described as a consequence of hub-owned `Application` CRs, not as a general spoke-versus-CSOC distinction.

## Conclusion

The earlier report overstated the difference between Option A and Option B in the wrong place. The important distinction is not where the workloads run. The workloads are supposed to run in the spoke in both options.

The important distinction is where the ArgoCD `Application` CRs live and which ArgoCD controller reconciles them. Once that is stated clearly, the Karpenter issue becomes easier to explain and the implementation tradeoffs become much more precise.
