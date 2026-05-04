# Spoke1 Fleet Directory

This directory contains the KRO instance CRs and values files for the `spoke1`
cluster. `argocd/bootstrap/fleet-instances.yaml` applies these manifests to the
`spoke1` destination cluster itself, not to CSOC.

## Layout

```text
argocd/fleet/spoke1/
├── infrastructure/
│   ├── infrastucture-values.yaml
│   └── instances.yaml
├── cluster-level-resources/
│   ├── cluster-values.yaml
│   └── app.yaml                  # AwsGen3ClusterResources2
└── spoke1dev.rds-pla.net/
    ├── values.yaml
    └── app.yaml                  # AwsGen3Helm1
```

## Waves

| Wave | Resource | File | Purpose |
|------|----------|------|---------|
| 14 | `ConfigMap/infrastructure-values` | `infrastructure/infrastucture-values.yaml` | Shared infrastructure inputs |
| 15-25 | `AwsGen3*1` infra instances | `infrastructure/instances.yaml` | Network, DNS, storage, compute, database, search, OIDC, IAM, messaging, advanced |
| 27 | `AwsGen3ClusterResources2/gen3` | `cluster-level-resources/app.yaml` | Registers the spoke cluster in spoke ArgoCD and creates the parent `cluster-level-resources` Application |
| 30 | `AwsGen3Helm1/gen3` | `spoke1dev.rds-pla.net/app.yaml` | Creates the parent `gen3-helm` Application |

## Important topology

- The `fleet-instances` ApplicationSet targets `destination.name: spoke1`, so these KRO instances reconcile on the spoke cluster.
- `AwsGen3ClusterResources2` is the EKS managed-ArgoCD path. It assumes the EKS ArgoCD capability is enabled out-of-band and then creates spoke-local `Application` CRs in the `argocd` namespace.
- `AwsGen3Helm1` also creates its `Application` CR in the spoke cluster. It uses the registered cluster name from `cluster-resources-bridge` because the managed capability expects `destination.name`.
- `cluster-values.yaml` and `values.yaml` are excluded from recursive pickup and are consumed only through ArgoCD multi-source `$values` references.

## Bridge chain

`AwsGen3ClusterResources2` reads:

- `compute-bridge`
- `iam-bridge`

It produces:

- `cluster-resources-bridge`

`AwsGen3Helm1` then reads `cluster-resources-bridge` plus the other upstream
bridges to parameterize the `gen3-helm` Application.

## Cluster-level-resources source model

`cluster-level-resources/app.yaml` creates a parent ArgoCD `Application` that
points at the upstream `uc-cdis/gen3-helm` `helm/cluster-level-resources`
chart. That parent Application is reconciled by the spoke's managed ArgoCD
capability, so the child addon `Application` CRs also live in the spoke.

This is Option A behavior. It is not the hub-owned Option B design.
