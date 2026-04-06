# 05 — Cluster Fleet & Test RGDs ✅ Complete

> All work in this plan is implemented. This file is retained for reference.
>
> **Implemented**:
> - `argocd/cluster-fleet/local-aws-dev/` — full directory tree (19 files: 7 infra + 9 tests + 3 cluster support)
> - 9 test RGD templates in `argocd/charts/resource-groups/templates/` (krotest01–08)
> - `argocd/charts/resource-groups/Chart.yaml` bumped to 0.2.0

---

<!-- Original plan content below (reference only) -->

# 05 — Cluster Fleet & Test RGDs Plan (ORIGINAL)

Covers: `cluster-fleet/local-aws-dev/` directory, test RGD templates, and
chart version alignment.

---

## 1. Overview

gen3-dev contains a complete cluster fleet definition for the local Kind CSOC
(`local-aws-dev/`) plus 9 KRO capability test RGDs. None of this exists in
gen3-kro today. All content is additive — no existing gen3-kro files are
modified by this section.

---

## 2. Cluster Fleet Directory: `local-aws-dev/`

### Target Path

```
argocd/cluster-fleet/local-aws-dev/
├── infrastructure/
│   ├── spoke1-foundation.yaml
│   ├── spoke1-database.yaml
│   ├── spoke1-search.yaml
│   ├── spoke1-compute.yaml
│   ├── spoke1-appiam.yaml
│   ├── spoke1-helm.yaml           # Not in gen3-kro spoke1
│   └── spoke1-observability.yaml  # Not in gen3-kro spoke1
├── tests/
│   ├── krotest01-foreach.yaml
│   ├── krotest02-includewhen.yaml
│   ├── krotest03-bridge-producer.yaml
│   ├── krotest04-bridge-consumer.yaml
│   ├── krotest05-cel.yaml
│   ├── krotest06-sg-conditional.yaml
│   ├── krotest07a-cross-rgd-producer.yaml
│   ├── krotest07b-cross-rgd-consumer.yaml
│   └── krotest08-chained-orvalue.yaml
├── cluster-resources/
│   ├── app.yaml
│   └── cluster-values.yaml
└── spoke1.rds-pla.net/
    └── values.yaml
```

### Action: ADD entire directory tree

Copy from gen3-dev as-is. These files are KRO custom resource instances
(YAML manifests) consumed by the `local-infra-instances.yaml` bootstrap
ApplicationSet's directory generator.

### Infrastructure Files Comparison

| File | In gen3-kro spoke1? | Notes |
|------|-------------------|-------|
| spoke1-foundation.yaml | Yes | Same structure; local may have different spec values |
| spoke1-database.yaml | Yes | Same structure |
| spoke1-search.yaml | Yes | Same structure |
| spoke1-compute.yaml | Yes | Same structure |
| spoke1-appiam.yaml | Yes | Same structure |
| spoke1-helm.yaml | **No** | Tier 5 — AwsGen3Helm1 instance (RGD-managed ArgoCD App) |
| spoke1-observability.yaml | **No** | Tier 6 — AwsGen3Observability1 instance |

The Helm and Observability instances are newer tiers that exist in gen3-dev's
modular RGD design but haven't been promoted to gen3-kro's spoke1 yet. They
are safe to include in `local-aws-dev/` — they only apply to the local CSOC
and do not affect the EKS fleet.

### Test Files

All 9 test instance files are unique to the local CSOC. They exercise KRO
capabilities (forEach, includeWhen, bridge ConfigMap, CEL expressions,
conditional SGs, cross-RGD status flow, chained orValue). Tests 1-5 and 8
are pure Kubernetes (ConfigMaps) — no AWS cost. Tests 6, 7a, 7b create real
AWS SecurityGroups via ACK EC2.

---

## 3. Test RGD Templates

### Target Path

```
argocd/charts/resource-groups/templates/
├── (existing 9 production RGDs — no changes)
├── krotest01-foreach-rg.yaml              # NEW
├── krotest02-includewhen-rg.yaml          # NEW
├── krotest03-bridge-producer-rg.yaml      # NEW
├── krotest04-bridge-consumer-rg.yaml      # NEW
├── krotest05-cel-expressions-rg.yaml      # NEW
├── krotest06-sg-conditional-rg.yaml       # NEW
├── krotest07a-cross-rgd-producer-rg.yaml  # NEW
├── krotest07b-cross-rgd-consumer-rg.yaml  # NEW
└── krotest08-chained-orvalue-rg.yaml      # NEW
```

### Action: ADD all 9 test RGD files

Copy from gen3-dev `argocd/charts/resource-groups/templates/`. These are
ResourceGraphDefinition YAML files wrapped in Helm template guards
(`{{- if .Values.enableTests }}`  or unconditionally included — verify
each file's guard pattern).

### Guard Pattern Decision

**Option A**: Include test RGDs unconditionally (same as production RGDs).
ArgoCD will deploy them to any cluster matching the kro-csoc-rgs selector.
The test *instances* only exist in `local-aws-dev/tests/`, so the RGDs
deploy but no test CRs are created on EKS clusters. This is the simpler
approach — RGDs are lightweight (just schema definitions).

**Option B**: Wrap test RGDs in a Helm values guard:
```yaml
{{- if .Values.enableTestRGDs }}
# ... RGD content ...
{{- end }}
```
This requires adding `enableTestRGDs: true` to the local addons config and
`enableTestRGDs: false` to the EKS addons config. More complexity for
marginal benefit (unused RGDs consume no resources).

**Recommendation**: Option A — include unconditionally. RGDs without instances
are inert. If the user prefers Option B, the guard value must be added to
both addons files and the chart's `values.yaml`.

---

## 4. Chart Version Bump

### `argocd/charts/resource-groups/Chart.yaml`

```yaml
# gen3-kro (current)
version: 0.1.0

# gen3-dev (current)
version: 0.2.0
```

**Action: MODIFY** — bump gen3-kro's version to `0.2.0` (or higher) to reflect
the addition of test RGDs and any template changes. The appVersion field should
also be updated if present.

### `argocd/charts/resource-groups/README.md`

**Action: MODIFY** — add a section documenting the test RGDs (names, purposes,
which create AWS resources).

---

## 5. No Changes to existing gen3-kro Cluster Fleet

`argocd/cluster-fleet/spoke1/` is untouched. The EKS fleet continues to use
its existing infrastructure files. The spoke1-helm.yaml and
spoke1-observability.yaml files can be promoted to gen3-kro's spoke1/ later
as a separate effort — this merge plan does not include that promotion.

---

## 6. `_example/` Directory

Both repos have `argocd/cluster-fleet/_example/`. Verify they are compatible.
If gen3-dev's `_example/` has additional content (e.g., test instance examples),
merge the additions into gen3-kro's `_example/`. This is a low-priority cosmetic
change.

---

## 7. File-by-File Checklist

| # | File | Action | AWS Resources? |
|---|------|--------|---------------|
| 1 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-foundation.yaml` | ADD | Yes (VPC, SGs, IAM, KMS) |
| 2 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-database.yaml` | ADD | Yes (RDS) |
| 3 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-search.yaml` | ADD | Yes (OpenSearch) |
| 4 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-compute.yaml` | ADD | Yes (EKS nodegroups) |
| 5 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-appiam.yaml` | ADD | Yes (IAM roles) |
| 6 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-helm.yaml` | ADD | No (ArgoCD App) |
| 7 | `cluster-fleet/local-aws-dev/infrastructure/spoke1-observability.yaml` | ADD | No (ArgoCD App) |
| 8 | `cluster-fleet/local-aws-dev/tests/krotest01-foreach.yaml` | ADD | No (ConfigMaps) |
| 9 | `cluster-fleet/local-aws-dev/tests/krotest02-includewhen.yaml` | ADD | No (ConfigMaps) |
| 10 | `cluster-fleet/local-aws-dev/tests/krotest03-bridge-producer.yaml` | ADD | No (ConfigMaps) |
| 11 | `cluster-fleet/local-aws-dev/tests/krotest04-bridge-consumer.yaml` | ADD | No (ConfigMaps) |
| 12 | `cluster-fleet/local-aws-dev/tests/krotest05-cel.yaml` | ADD | No (ConfigMaps) |
| 13 | `cluster-fleet/local-aws-dev/tests/krotest06-sg-conditional.yaml` | ADD | Yes (ACK EC2 SGs) |
| 14 | `cluster-fleet/local-aws-dev/tests/krotest07a-cross-rgd-producer.yaml` | ADD | Yes (ACK EC2 SGs) |
| 15 | `cluster-fleet/local-aws-dev/tests/krotest07b-cross-rgd-consumer.yaml` | ADD | Yes (ACK EC2 SGs) |
| 16 | `cluster-fleet/local-aws-dev/tests/krotest08-chained-orvalue.yaml` | ADD | No (ConfigMaps) |
| 17 | `cluster-fleet/local-aws-dev/cluster-resources/app.yaml` | ADD | No |
| 18 | `cluster-fleet/local-aws-dev/cluster-resources/cluster-values.yaml` | ADD | No |
| 19 | `cluster-fleet/local-aws-dev/spoke1.rds-pla.net/values.yaml` | ADD | No |
| 20 | `charts/resource-groups/templates/krotest01-foreach-rg.yaml` | ADD | — |
| 21 | `charts/resource-groups/templates/krotest02-includewhen-rg.yaml` | ADD | — |
| 22 | `charts/resource-groups/templates/krotest03-bridge-producer-rg.yaml` | ADD | — |
| 23 | `charts/resource-groups/templates/krotest04-bridge-consumer-rg.yaml` | ADD | — |
| 24 | `charts/resource-groups/templates/krotest05-cel-expressions-rg.yaml` | ADD | — |
| 25 | `charts/resource-groups/templates/krotest06-sg-conditional-rg.yaml` | ADD | — |
| 26 | `charts/resource-groups/templates/krotest07a-cross-rgd-producer-rg.yaml` | ADD | — |
| 27 | `charts/resource-groups/templates/krotest07b-cross-rgd-consumer-rg.yaml` | ADD | — |
| 28 | `charts/resource-groups/templates/krotest08-chained-orvalue-rg.yaml` | ADD | — |
| 29 | `charts/resource-groups/Chart.yaml` | MODIFY | — |
| 30 | `charts/resource-groups/README.md` | MODIFY | — |
