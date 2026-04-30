# Resource Groups — KRO ResourceGraphDefinitions

KRO RGDs for the gen3-kro CSOC EKS cluster. Deployed by ArgoCD via
`kro-eks-rgs` (wave 10).

## Naming

- Modular: `AwsGen3<Component><Version>` (e.g. `AwsGen3Network1`)
- Filename: `<lowercase>-rg.yaml`, metadata.name: lowercase no hyphens

## RGDs

| Tier | RGD | Kind | Bridge Contract |
|------|-----|------|-----------------|
| 0 | `awsgen3network1` | AwsGen3Network1 | Produces `networkBridge` |
| 0.5 | `awsgen3dns1` | AwsGen3Dns1 | Produces `dnsBridge` |
| 0.5 | `awsgen3storage1` | AwsGen3Storage1 | Reads `networkBridge`, produces `storageBridge` |
| 1 | `awsgen3database1` | AwsGen3Database1 | Reads `networkBridge`, produces `databaseBridge` |
| 2 | `awsgen3search1` | AwsGen3Search1 | Reads `networkBridge`, produces `searchBridge` |
| 3 | `awsgen3compute1` | AwsGen3Compute1 | Reads `networkBridge`, produces `computeBridge` |
| 4 | `awsgen3messaging1` | AwsGen3Messaging1 | Produces `messagingBridge` |
| 4 | `awsgen3oidc1` | AwsGen3OIDC1 | Reads `computeBridge`, produces `oidcBridge` |
| 4.5 | `awsgen3clusterresources1` | AwsGen3ClusterResources1 | Reads `computeBridge`, produces `clusterResourcesBridge` |
| 5 | `awsgen3appiam1` | AwsGen3AppIAM1 | Reads `oidcBridge` + `storageBridge`, produces `iamBridge` |
| 5 | `awsgen3helm1` | AwsGen3Helm1 | Reads all upstream bridges |
| 7 | `awsgen3advanced1` | AwsGen3Advanced1 | Produces `advancedBridge` |

`AwsGen3Network1` owns the single upstream network bridge for the feature-flagged
prep slices (database, compute, search). Optional bridge keys are emitted with
the same feature-flag ternary used to guard those slices so each active RGD
still produces exactly one bridge ConfigMap.

## Cross-Tier Data Flow

```
Network1 ─────── networkBridge ───────► Storage1, Database1, Search1, Compute1
DNS1 ─────────── dnsBridge ───────────► Helm1
Storage1 ─────── storageBridge ───────► AppIAM1, Helm1
Database1 ────── databaseBridge ──────► Helm1
Search1 ──────── searchBridge ────────► Helm1
Compute1 ─────── computeBridge ───────► OIDC1, ClusterResources1, Helm1
Messaging1 ───── messagingBridge ─────► Helm1
OIDC1 ────────── oidcBridge ──────────► AppIAM1
AppIAM1 ──────── iamBridge ───────────► Helm1
Advanced1 ────── advancedBridge ──────► Helm1
```

Bridge key naming: kebab-case (`vpc-id`, `nat-gateway-id`).
Access in templates: `${foundationBridge.data['vpc-id']}`.

## Modifying RGDs

### Non-Breaking Changes (safe, fully automatic)

- Adding resources (with or without schema changes)
- Adding schema fields **with defaults**
- Modifying template values or CEL expressions
- Removing resources (KRO garbage-collects them)

Procedure: edit YAML → `git push` → ArgoCD auto-syncs → KRO reconciles
all instances (~15s).

### Breaking Changes (blocked by KRO)

- Removing or renaming schema spec/status fields
- KRO rejects the CRD update: `breaking changes detected`
- RGD goes **Inactive**; instances keep running but finalizer blocks deletion

**Recovery:**
```bash
kubectl patch <kind> <name> -n <ns> -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl delete <kind> <name> -n <ns>
kubectl delete crd <kind-plural>.kro.run
# KRO recreates CRD from current RGD in ~10s
```

**Recommended:** Never remove schema fields. Version the RGD instead
(create v2 with new schema, migrate instances, delete v1).

## Creating a New Version

1. Copy: `cp awsgen3network1-rg.yaml awsgen3network2-rg.yaml`
2. Update `metadata.name` → `awsgen3network2`
3. Update `kind` → `AwsGen3Network2`
4. Make schema changes freely (new CRD, no breaking-change risk)
5. Both versions coexist as separate CRDs
