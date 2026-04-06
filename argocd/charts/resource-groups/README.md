# Resource Groups — KRO ResourceGraphDefinitions

KRO RGDs for the gen3-kro CSOC EKS cluster. Deployed by ArgoCD via
`kro-eks-rgs` (wave 10).

## Naming

- Monolithic: `AwsGen3<Component><Version>Flat` (e.g. `AwsGen3Infra1Flat`)
- Modular: `AwsGen3<Component><Version>` (e.g. `AwsGen3Foundation1`)
- Filename: `<lowercase>-rg.yaml`, metadata.name: lowercase no hyphens

## RGDs

### Monolithic (reference only)

| RGD | Kind | Resources | Status |
|-----|------|-----------|--------|
| `awsgen3infra1flat` | AwsGen3Infra1Flat | 31+ | Reference — spoke1 uses this |

### Modular (7-tier architecture)

| Tier | RGD | Kind | Depends On | Cost |
|------|-----|------|------------|------|
| 0 | `awsgen3foundation1` | AwsGen3Foundation1 | — (standalone) | ~$37/mo |
| 1 | `awsgen3database1` | AwsGen3Database1 | databasePrepBridge | ~$45-350/mo |
| 2 | `awsgen3search1` | AwsGen3Search1 | searchPrepBridge + foundationBridge | ~$30-200/mo |
| 3 | `awsgen3compute1` | AwsGen3Compute1 | computePrepBridge + foundationBridge | ~$350/mo (v1, see compute2) |
| 3 | `awsgen3compute2` | AwsGen3Compute2 | computePrepBridge + foundationBridge | ~$350/mo |
| 4 | `awsgen3appiam1` | AwsGen3AppIAM1 | foundationBridge + computeBridge | ~$5/mo |
| 5 | `awsgen3helm1` | AwsGen3Helm1 | foundationBridge + computeBridge | ~$0 (pods) |
| 6 | `awsgen3observability1` | AwsGen3Observability1 | computeBridge | ~$0-50/mo |

Foundation1 produces bridge ConfigMaps consumed by higher tiers via
`externalRef`. It absorbs all prep infrastructure (security groups,
IAM roles, DB subnets, KMS keys) behind feature flags
(`databaseEnabled`, `computeEnabled`, `searchEnabled`).

## Cross-Tier Data Flow

```
Foundation1 ─┬─ foundationBridge ──────► Compute2, Search1, AppIAM1, Helm1
             ├─ databasePrepBridge ────► Database1
             ├─ searchPrepBridge ──────► Search1
             └─ computePrepBridge ─────► Compute2

Compute2 ────── computeBridge ─────────► AppIAM1, Helm1, Observability1
Database1 ───── databaseBridge ────────► Helm1 (optional)
AppIAM1 ─────── appIAMBridge ─────────► Helm1 (optional)
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

1. Copy: `cp awsgen3foundation1-rg.yaml awsgen3foundation2-rg.yaml`
2. Update `metadata.name` → `awsgen3foundation2`
3. Update `kind` → `AwsGen3Foundation2`
4. Make schema changes freely (new CRD, no breaking-change risk)
5. Both versions coexist as separate CRDs
