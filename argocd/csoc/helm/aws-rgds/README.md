# Resource Groups — KRO ResourceGraphDefinitions

KRO RGDs for the gen3-kro CSOC EKS cluster. Deployed by ArgoCD via
`kro-eks-rgs`; RGD resources use dependency sync waves 15, 20, 25, 30, and 35.

## Naming

- Modular: `AwsGen3<Component><Version>` (e.g. `AwsGen3NetworkSecurity1`)
- Filename: `<lowercase>-rg.yaml`, metadata.name: lowercase no hyphens

## RGDs

| Tier | RGD | Kind | Bridge Contract |
|------|-----|------|-----------------|
| 0 | `awsgen3networksecurity1` | AwsGen3NetworkSecurity1 | Produces `network-security-bridge` |
| 0 | `awsgen3domainsecurity1` | AwsGen3DomainSecurity1 | Produces `domain-security-bridge` |
| 0 | `awsgen3messaging1` | AwsGen3Messaging1 | Produces `messaging-bridge` |
| 1 | `awsgen3storage1` | AwsGen3Storage1 | Reads `network-security-bridge`, produces `storage-bridge` |
| 1 | `awsgen3database1` | AwsGen3Database1 | Reads `network-security-bridge`, produces `database-bridge` |
| 1 | `awsgen3compute1` | AwsGen3Compute1 | Reads `network-security-bridge`, produces `compute-bridge` |
| 2 | `awsgen3spokeaccess1` | AwsGen3SpokeAccess1 | Reads `compute-bridge`, produces `spoke-access-bridge` |
| 2 | `awsgen3platformiam1` | AwsGen3PlatformIAM1 | Reads `compute-bridge` + `storage-bridge`, produces `platform-iam-bridge` |
| 2 | `awsgen3appiam1` | AwsGen3AppIAM1 | Reads `compute-bridge` + `storage-bridge`, produces `app-iam-bridge` |
| 3 | `awsgen3platformhelm1` | AwsGen3PlatformHelm1 | Reads `compute-bridge` + `platform-iam-bridge` + `spoke-access-bridge`, produces `platform-helm-bridge` |
| 4 | `awsgen3apphelm1` | AwsGen3AppHelm1 | Reads all upstream bridges, produces `apphelm-bridge` |

`AwsGen3NetworkSecurity1` owns the single upstream network bridge for the feature-flagged
prep slices (database, compute, search). Optional bridge keys are emitted with
the same feature-flag ternary used to guard those slices so each active RGD
still produces exactly one bridge ConfigMap.

## Cross-Tier Data Flow

```
NetworkSecurity1 ─── network-security-bridge ───► Storage1, Database1, Compute1
DomainSecurity1 ──── domain-security-bridge ────► AppHelm1
Storage1 ─────────── storage-bridge ────────────► PlatformIAM1, AppIAM1, AppHelm1
Database1 ────────── database-bridge ───────────► AppHelm1
Compute1 ─────────── compute-bridge ────────────► SpokeAccess1, PlatformIAM1, AppIAM1, PlatformHelm1, AppHelm1
SpokeAccess1 ─────── spoke-access-bridge ───────► PlatformHelm1
PlatformIAM1 ─────── platform-iam-bridge ───────► PlatformHelm1
PlatformHelm1 ────── platform-helm-bridge ──────► AppHelm1
AppIAM1 ──────────── app-iam-bridge ────────────► AppHelm1
Messaging1 ───────── messaging-bridge ──────────► AppHelm1
```

Bridge key naming: kebab-case (`vpc-id`, `nat-gateway-id`).
Access in templates: `${networkSecurityBridge.data['vpc-id']}`.

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
