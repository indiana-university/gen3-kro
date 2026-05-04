# Spoke Application Hierarchy

This document describes the actual reconciliation path for the spoke fleet.

## Control flow

```text
CSOC ArgoCD
  -> fleet-instances ApplicationSet
  -> spoke1-fleet-instances Application
  -> applies KRO instance CRs into the spoke1 cluster

spoke1 KRO
  -> AwsGen3ClusterResources2
  -> AwsGen3Helm1

spoke1 managed ArgoCD capability
  -> reconciles parent Applications created by those KRO instances
  -> reconciles child addon Applications from cluster-level-resources
```

## Key point

The KRO instance CRs for a spoke do not live on CSOC. `fleet-instances`
targets the spoke cluster directly, so the generated `Application` CRs are also
created on the spoke unless you introduce a separate CSOC-side producer path.

## Instances

| Kind | Wave | What it creates |
|------|------|-----------------|
| `AwsGen3ClusterResources2` | 27 | A spoke-local ArgoCD cluster registration Secret, the parent `cluster-level-resources` Application, and `cluster-resources-bridge` |
| `AwsGen3Helm1` | 30 | The parent `gen3-helm` Application and `gen3helm-bridge` |

## Why `destination.name` matters

Amazon EKS managed ArgoCD does not use the open-source local-cluster default
`https://kubernetes.default.svc`. The target cluster must be registered and
referenced by name. `AwsGen3ClusterResources2` therefore registers the spoke
cluster and publishes that registered name in `cluster-resources-bridge`, which
`AwsGen3Helm1` consumes.

## Option mapping

- Option A: implemented path. `Application` CRs live in the spoke and the spoke's managed ArgoCD capability reconciles them.
- Option B: not implemented end-to-end in `gen3-kro`. It would require a CSOC-side producer path because changing only the parent Application destination does not move the producing KRO instance out of the spoke.
