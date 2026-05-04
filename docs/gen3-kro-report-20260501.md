# gen3-kro Progress Report

**Prepared for:** Alan Walsh  
**Date:** 2026-05-04  
**Scope:** spoke1 Gen3 deployment status

## What landed

- The infrastructure RGDs and bridge chain are in place for spoke1.
- The `gen3-build` `cluster-level-resources` chart now supports a future
  hub-owned experiment through `destinationServer` and the new
  `karpenter-node-configs` wrapper chart.
- The repo now has an explicit EKS managed-ArgoCD versioned path through
  [`AwsGen3ClusterResources2`](../argocd/charts/resource-groups/templates/07-clusterresources2-rg.yaml).

## Current topology

- `fleet-instances` applies the KRO instance CRs into the spoke cluster.
- `AwsGen3ClusterResources2` creates the parent `cluster-level-resources`
  Application in the spoke cluster.
- `AwsGen3Helm1` creates the parent `gen3-helm` Application in the spoke
  cluster.
- The spoke's EKS managed ArgoCD capability is therefore the reconciler for the
  active application path.

## Recommended path

Option A is the implemented and aligned path in this repo:

- use the EKS ArgoCD capability for the spoke
- keep the relevant `Application` CRs in the spoke
- continue to feed `AwsGen3Helm1` from `cluster-resources-bridge`

Option B remains a future control-plane refactor. The chart changes are done,
but a real hub-owned implementation also needs a CSOC-side producer path
because the current producer CRs are created on the spoke.

## Remaining checks

1. Verify the ArgoCD capability is enabled on the spoke before wave 27.
2. Verify the managed ArgoCD project policy allows the registered spoke target.
3. Verify the CoreDNS service IP in `cluster-values.yaml`.
4. Validate first live spoke sync for `AwsGen3ClusterResources2` and `AwsGen3Helm1`.
