# 02 — ArgoCD Integration ✅ Complete

> All work in this plan is implemented. This file is retained for reference.
>
> **Implemented**:
> - Phase 1: `kro-eks-rgs` → `kro-csoc-rgs` rename in `argocd/addons/csoc/addons.yaml`
> - Phase 3: `argocd/addons/local/addons.yaml` created; `csoc-addons.yaml` parameterized via `addons_config_path`; `local-infra-instances.yaml` added
> - Phase 6 (Terraform): `addons_config_path` added to `terraform/catalog/modules/aws-csoc/locals.tf`

---

<!-- Original plan content below (reference only) -->

# 02 — ArgoCD Integration Plan (ORIGINAL)

Covers: addons, bootstrap ApplicationSets, and the application-sets chart.

---

## 1. Unified RGD Addon Key: `kro-csoc-rgs`

### Problem

gen3-dev uses `kro-local-rgs` and gen3-kro uses `kro-eks-rgs`. Both serve the
same purpose: deploy ResourceGraphDefinitions from `argocd/charts/resource-groups`.
The name divergence creates confusion and blocks a single-repo solution.

### Solution

Rename both to **`kro-csoc-rgs`** — the CSOC deploys RGDs regardless of whether
it's a local Kind cluster or an EKS cluster.

### Changes

#### `argocd/addons/csoc/addons.yaml` (gen3-kro — EKS CSOC)

```yaml
# BEFORE
kro-eks-rgs:
  enabled: true
  type: manifest
  ...
  selector:
    matchExpressions:
      - key: fleet_member
        operator: In
        values: ['control-plane']
      - key: enable_kro_eks_rgs        # ← this selector key also changes
        operator: In
        values: ['true']

# AFTER
kro-csoc-rgs:
  enabled: true
  type: manifest
  ...
  selector:
    matchExpressions:
      - key: fleet_member
        operator: In
        values: ['control-plane']
      - key: enable_kro_csoc_rgs       # ← renamed selector key
        operator: In
        values: ['true']
```

**Impact on EKS cluster secrets**: The Terraform `argocd-bootstrap` module
creates cluster secrets with label `enable_kro_eks_rgs: "true"`. This label
must be updated to `enable_kro_csoc_rgs: "true"` in the Terraform module.

**Affected Terraform files** (in gen3-kro):
- `terraform/catalog/modules/argocd-bootstrap/` — cluster secret labels
- Search for `enable_kro_eks_rgs` across all `.tf` files

#### `argocd/addons/local/addons.yaml` (brought from gen3-dev)

```yaml
# BEFORE (in gen3-dev)
kro-local-rgs:
  enabled: true
  type: manifest
  ...

# AFTER (in gen3-kro)
kro-csoc-rgs:
  enabled: true
  type: manifest
  namespace: kro
  annotationsAppSet:
    argocd.argoproj.io/sync-wave: "10"
  path: 'argocd/charts/resource-groups'
  chartRepository: '{{.metadata.annotations.addons_repo_url}}'
  targetRevision: '{{.metadata.annotations.addons_repo_revision}}'
  selector:
    matchExpressions:
      - key: fleet_member
        operator: In
        values: ['control-plane']
```

Note: The local addons don't need the `enable_kro_csoc_rgs` selector key since
the local cluster secret is manually created by `kind-local-test.sh` and already
has `fleet_member: control-plane`. The EKS variant adds the extra selector for
fine-grained control. This asymmetry is acceptable — matching on `fleet_member`
alone is sufficient for local.

---

## 2. Local Addons File

### Source

Copy `argocd/addons/local/addons.yaml` from gen3-dev into gen3-kro at the same
relative path: `argocd/addons/local/addons.yaml`.

### Required Modifications

1. **Rename key** `kro-local-rgs` → `kro-csoc-rgs` (see above)
2. **Verify ACK controller versions** match gen3-kro's `csoc/addons.yaml` — update any
   that are behind. Current discrepancies:

   | Controller | gen3-dev (local) | gen3-kro (csoc) | Action |
   |------------|-----------------|-----------------|--------|
   | ec2 | 1.10.1 | 1.10.1 | Match ✓ |
   | eks | 1.12.0 | 1.12.0 | Match ✓ |
   | iam | 1.6.2 | 1.6.2 | Match ✓ |
   | kms | 1.2.2 | 1.2.2 | Match ✓ |
   | opensearchservice | 1.2.3 | 1.2.3 | Match ✓ |
   | rds | 1.7.7 | 1.7.7 | Match ✓ |
   | s3 | 1.3.2 | 1.3.2 | Match ✓ |
   | secretsmanager | 1.2.2 | 1.2.2 | Match ✓ |
   | sqs | 1.4.2 | 1.4.2 | Match ✓ |

3. **Keep `ignoreDifferences` blocks** — essential for local CSOC where
   `kind-local-test.sh inject-creds` patches ACK deployments with env vars.
4. **Keep the local syncPolicy** — includes `SkipDryRunOnMissingResource=true`
   which gen3-kro's csoc addons doesn't have (EKS CRDs exist via Terraform).
5. **No IRSA annotations** — local addons intentionally omit
   `eks.amazonaws.com/role-arn` since Kind has no OIDC provider.
6. **Fewer ACK controllers** — local only has 9 vs gen3-kro's 20. This is intentional;
   local CSOC only needs controllers for the RGD tiers it tests.
7. **chartRepository format** — local uses bare URL (no `oci://` prefix), EKS uses
   `oci://` prefix. Verify the application-sets chart handles both correctly.
   The `_application_set.tpl` template should already handle this via the OCI
   repo secrets created in kind-local-test.sh.

---

## 3. Bootstrap ApplicationSets

### Problem: Duplicate Bootstrap Files

`csoc-addons.yaml` and the proposed `local-addons.yaml` perform identical functions —
both create an ApplicationSet that drives addon deployment from an `addons.yaml` values
file. Adding a second file creates unnecessary duplication.

### Solution: Parameterize `csoc-addons.yaml` via Cluster Annotation

Modify `argocd/bootstrap/csoc-addons.yaml` so the `valueFiles` path comes from a
cluster annotation (`addons_config_path`) rather than being hardcoded to
`addons/csoc/addons.yaml`. A single bootstrap file then handles both clusters:

```yaml
# In csoc-addons.yaml — BEFORE
valueFiles:
  - '$addons/argocd/addons/csoc/addons.yaml'

# AFTER
valueFiles:
  - '$addons/{{.metadata.annotations.addons_config_path}}'
```

Each cluster secret sets the annotation to the appropriate variant:
- **EKS cluster** (via Terraform): `addons_config_path: argocd/addons/csoc/addons.yaml`
- **Local cluster** (via `kind-local-test.sh`): `addons_config_path: argocd/addons/local/addons.yaml`

**Impact on Terraform**: The `argocd-bootstrap` module must add
`addons_config_path: argocd/addons/csoc/addons.yaml` to EKS cluster secret annotations.
Search for the cluster secret creation in `terraform/catalog/modules/argocd-bootstrap/`.

### `argocd/bootstrap/local-infra-instances.yaml` — ADD

Copy from gen3-dev. This file is unique to the local workflow (no equivalent in EKS
which uses `fleet-infra-instances.yaml`). Key differences:
- **Two directory sources** — infrastructure/ AND tests/ (fleet only has infrastructure/)
- **Selector** — `fleet_member: control-plane` (fleet uses `fleet-spoke-infra`)
- **syncPolicy.preserveResourcesOnDeletion: true** — same as fleet
- **ignoreDifferences on Namespace** — prevents fights with manual NS annotations

**No modifications needed** — already uses annotation-based repo URLs.

### No Changes to Other Bootstrap Files

`fleet-infra-instances.yaml`, `fleet-cluster-resources.yaml`, `fleet-gen3.yaml`,
`ack-multi-acct.yaml` — all untouched.

---

## 4. Application-Sets Chart Compatibility

The `argocd/charts/application-sets/` chart is **identical** in both repos and
requires **no changes**. It renders one ApplicationSet per addon entry in the
addons.yaml file. The chart:

- Reads addon entries from the values file
- Respects `type: manifest` (directory source) and `type: helm` (chart source)
- Passes through `selector`, `ignoreDifferences`, `annotationsAppSet`
- Handles OCI repos via the repository secrets

The `_application_set.tpl` template processes each addon key uniformly. Adding
`kro-csoc-rgs` as a key name is seamless — it's just a YAML key name.

---

## 5. ArgoCD Cluster Secret (Local CSOC)

Created by `kind-local-test.sh stage_install()`. The secret defines:

```yaml
metadata:
  name: local-aws-dev
  labels:
    fleet_member: control-plane
    ack_management_mode: self_managed
  annotations:
    addons_repo_url: "https://github.com/indiana-university/gen3-kro.git"  # ← updated
    addons_repo_revision: "main"
    addons_repo_basepath: "argocd/"
    addons_config_path: "argocd/addons/local/addons.yaml"                  # ← NEW
    aws_region: "us-east-1"
    aws_account_id: "<resolved at runtime>"
```

**Key changes**:
- `addons_repo_url` must point to **gen3-kro** (not gen3-dev) — configured via `GIT_REPO_URL` constant.
- `addons_config_path` is **new** — tells the shared `csoc-addons.yaml` bootstrap ApplicationSet which addons file to use for this cluster.

---

## 6. Verification

After merge, these ArgoCD resources should exist on a local Kind cluster:

| Resource | Type | Source |
|----------|------|--------|
| `csoc-addons` | ApplicationSet | `bootstrap/csoc-addons.yaml` (shared with EKS) |
| `local-aws-dev-infra-instance` | Application | Generated by `local-infra-instances.yaml` |
| `kro-csoc-rgs-*` | Application | Generated by addon `kro-csoc-rgs` via application-sets |
| `ack-ec2-*` | Application | Generated by addon `ack-ec2` via application-sets |
| (other ACK controllers) | Application | Generated by respective addon entries |
| `self-managed-kro-*` | Application | Generated by addon `self-managed-kro` via application-sets |
