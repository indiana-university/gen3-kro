# Spoke1 Directory

This directory contains the per-spoke values files for the `spoke1` cluster.
`argocd/bootstrap/fleet-instances.yaml` applies the shared `kro-aws-instances`
chart with these values.

## Layout

```text
argocd/spokes/spoke1/
├── infrastucture-values.yaml     # kro-aws-instances override values
├── cluster-resources/
│   └── core-cluster-addons.yaml  # PlatformHelm1 $values file
└── spoke1dev.rds-pla.net/
    └── gen3-values.yaml          # AppHelm1 $values file
```

## Waves

| Wave | Resource | File | Purpose |
|------|----------|------|---------|
| 14 | `ConfigMap/infrastructure-values` | `infrastucture-values.yaml` | Shared infrastructure inputs |
| 15-35 | `AwsGen3*1` instances | rendered from `kro-aws-instances` | Network/security, storage, database, compute, IAM, platform Helm, app Helm |

## Important topology

- `AwsGen3PlatformHelm1` registers the spoke cluster and creates the parent platform add-ons `Application`.
- `AwsGen3AppHelm1` creates the parent `gen3-helm` `Application`.
- `core-cluster-addons.yaml` and `gen3-values.yaml` are consumed through ArgoCD multi-source `$values` references.

## Bridge chain

`AwsGen3PlatformHelm1` reads:

- `compute-bridge`
- `platform-iam-bridge`
- `spoke-access-bridge`

It produces:

- `platform-helm-bridge`

`AwsGen3AppHelm1` then reads `platform-helm-bridge` plus the other upstream
bridges to parameterize the `gen3-helm` Application.

## Aurora Secret Mirror

`infrastructure-values.yaml` includes the disabled
`data.databaseSecretMirror` and `instances.databaseSecretMirror` blocks. To turn
it on for spoke1, set `data.databaseSecretMirror.enabled: "true"` and
`instances.databaseSecretMirror.enabled: true`.

This keeps the RDS-managed password out of CSOC Kubernetes and out of ACK
`Secret.spec.secretString`. Lambda sees the password in memory during sync, the
mirror value exists in AWS Secrets Manager, and Gen3 Build later creates the
normal Kubernetes Secret inside the spoke cluster through External Secrets. A
one-shot initial invoke Job triggers the first sync; the EventBridge schedule
keeps the mirror repaired afterward.

## Cluster-level-resources source model

`AwsGen3PlatformHelm1` creates a parent ArgoCD `Application` that points at the
configured `helm/cluster-level-resources` chart and uses
`cluster-resources/core-cluster-addons.yaml` as its values file.

This is Option A behavior. It is not the hub-owned Option B design.
