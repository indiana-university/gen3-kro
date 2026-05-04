# Karpenter and ArgoCD Topology Report

**Date:** 2026-05-04  
**Scope:** `cluster-level-resources`, `AwsGen3ClusterResources*`, and Karpenter node-config rendering

## Executive summary

The important topology correction is this:

- `fleet-instances` applies the KRO instance CRs into the spoke cluster.
- Therefore `AwsGen3ClusterResources*` and `AwsGen3Helm1` create their parent ArgoCD `Application` CRs in the spoke cluster.
- For the EKS path, those `Application` CRs are reconciled by the managed ArgoCD capability attached to that spoke cluster.

That means Option A is the implemented path in this repo. Option B is not just a
chart-destination problem; it needs a different producer topology.

## Option A

Option A is now represented by [`AwsGen3ClusterResources2`](../argocd/charts/resource-groups/templates/07-clusterresources2-rg.yaml).

- It is versioned.
- It keeps the `Application` CRs in the spoke.
- It aligns with the EKS managed-capability model.
- It keeps cluster registration by name because managed ArgoCD expects `destination.name`.

The ArgoCD capability itself is still created outside KRO through Terraform
`aws_eks_capability`.

## Option B

The `gen3-build` chart work for Option B is implemented:

- `destinationServer` support is completed across the remaining child app templates.
- Karpenter raw node-config manifests can render as child `Application` CRs in hub-owned mode through the new `helm/karpenter-node-configs` chart.

But the `gen3-kro` side is still a larger architecture change:

- the producing KRO instance currently runs on the spoke
- its bridge inputs also live on the spoke
- changing only the parent Application destination does not relocate ownership to CSOC

A true Option B would need a CSOC-side producer path or bridge replication into
CSOC before hub-owned ownership is real.

## Why Karpenter was special

Most of the `cluster-level-resources` chart already renders ArgoCD `Application`
objects. Karpenter node-config files were different because they rendered raw:

- `EC2NodeClass`
- `NodePool`

Those resources have no ArgoCD destination field, so they can only be applied in
the cluster where the parent Application renders them. That is why the wrapper
chart was needed for the future Option B path.

## Current conclusion

- The repo now has an explicit Option A versioned graph.
- The repo now also has the chart changes needed for future Option B experiments.
- Hub-owned ownership is not implemented end-to-end because the producer
  topology still originates on the spoke.
