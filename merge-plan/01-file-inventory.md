# 01 — File Changes ✅ Complete

## Documentation & Instructions — ✅ Done

| # | File | Action | Status |
|---|------|--------|--------|
| G1 | `.github/copilot-instructions.md` | **ADD** | ✅ |
| G2 | `.github/instructions/argocd.instructions.md` | **ADD** | ✅ |
| G3 | `.github/instructions/kro-rgd.instructions.md` | **ADD** | ✅ |
| G4 | `.github/instructions/local-testing.instructions.md` | **ADD** | ✅ |
| G5 | `.github/instructions/scripts.instructions.md` | **ADD** | ✅ |
| G6 | `.github/instructions/dockerfile.instructions.md` | **ADD** | ✅ |
| G7 | `docs/local-csoc-guide.md` | **ADD** | ✅ |
| G8 | `docs/architecture.md` | **MODIFY** | ✅ |
| G9 | `docs/deployment-guide.md` | **MODIFY** | ✅ |
| G10 | `CONTRIBUTING.md` | **MODIFY** | ✅ |
| G11 | `README.md` | **MODIFY** | ✅ |

---

## H) Design Reports — ✅ Done

| # | File | Action | Status |
|---|------|--------|--------|
| H1 | `docs/design-reports/03-kro-capability-test-report.md` | **ADD** | ✅ |
| H2 | `docs/design-reports/05-rgd-update-behavior-test-report.md` | **ADD** | ✅ (already existed) |

---

## Gitignore — ✅ Done

| File | Action | Status |
|------|--------|--------|
| `.gitignore` | **MODIFY** — removed `.github/**` ignore line | ✅ |

---

## A) Scripts (`scripts/`)

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| A1 | `scripts/kind-local-test.sh` | **ADD** | gen3-dev | Primary Kind orchestrator. Modify GIT_REPO_URL to point to gen3-kro. Modify GIT_REPO_BASEPATH to `argocd/`. Update bootstrap file glob from `local-*.yaml` to match actual filenames. |
| A2 | `scripts/lib-logging.sh` | **SKIP** | — | Not brought over. `kind-local-test.sh` and `kro-status-report.sh` embed their own logging inline (same pattern as `container-init.sh`). |
| A3 | `scripts/kind-config.yaml` | **ADD** | gen3-dev | Kind cluster configuration (single control-plane, NodePort 30080). |
| A4 | `scripts/kro-status-report.sh` | **ADD** | gen3-dev | KRO + ACK status report generator. Update REPO_ROOT default. |
| A5 | `scripts/container-init.sh` | **NO-OP** | — | Untouched. EKS CSOC orchestrator stays as-is. |
| A6 | `scripts/install.sh` | **NO-OP** | — | Untouched. Terraform wrapper stays as-is. |
| A7 | `scripts/destroy.sh` | **NO-OP** | — | Untouched. |
| A8 | `scripts/mfa-session.sh` | **NO-OP** | — | Untouched. Already writes to `~/.aws/eks-devcontainer/`. kind-local-test.sh reads from `~/.aws/credentials` which is the container mount target. Both paths stay separate. |
| A9 | `scripts/namespace-infra-report.sh` | **NO-OP** | — | Untouched. |

---

## B) ArgoCD Addons (`argocd/addons/`)

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| B1 | `argocd/addons/local/addons.yaml` | **ADD** | gen3-dev | Local CSOC addons. Contains the subset of ACK controllers + `ignoreDifferences` blocks for credential injection. Rename key `kro-local-rgs` → `kro-csoc-rgs`. |
| B2 | `argocd/addons/csoc/addons.yaml` | **MODIFY** | — | Rename key `kro-eks-rgs` → `kro-csoc-rgs`. Update selector if needed. |

---

## C) ArgoCD Bootstrap (`argocd/bootstrap/`)

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| C1 | `argocd/bootstrap/local-addons.yaml` | **SKIP** | — | Eliminated. `csoc-addons.yaml` is parameterized via `addons_config_path` cluster annotation to serve both EKS and local CSOC without a duplicate file. See plan 02. |
| C2 | `argocd/bootstrap/local-infra-instances.yaml` | **ADD** | gen3-dev | Directory-source ApplicationSet with two sources (infrastructure/ + tests/). |
| C3 | `argocd/bootstrap/csoc-addons.yaml` | **MODIFY** | — | Parameterize the `valueFiles` path via `{{.metadata.annotations.addons_config_path}}` cluster annotation. EKS clusters use `addons/csoc/addons.yaml`; local cluster uses `addons/local/addons.yaml`. |
| C4 | `argocd/bootstrap/fleet-infra-instances.yaml` | **NO-OP** | — | Untouched. |
| C5 | `argocd/bootstrap/fleet-cluster-resources.yaml` | **NO-OP** | — | Untouched. |
| C6 | `argocd/bootstrap/fleet-gen3.yaml` | **NO-OP** | — | Untouched. |
| C7 | `argocd/bootstrap/ack-multi-acct.yaml` | **NO-OP** | — | Untouched. |

---

## D) ArgoCD Charts (`argocd/charts/`)

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| D1 | `argocd/charts/resource-groups/templates/krotest01-foreach-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D2 | `argocd/charts/resource-groups/templates/krotest02-includewhen-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D3 | `argocd/charts/resource-groups/templates/krotest03-bridge-producer-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D4 | `argocd/charts/resource-groups/templates/krotest04-bridge-consumer-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D5 | `argocd/charts/resource-groups/templates/krotest05-cel-expressions-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D6 | `argocd/charts/resource-groups/templates/krotest06-sg-conditional-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD (real ACK EC2) |
| D7 | `argocd/charts/resource-groups/templates/krotest07a-cross-rgd-producer-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD (real ACK EC2) |
| D8 | `argocd/charts/resource-groups/templates/krotest07b-cross-rgd-consumer-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD (real ACK EC2) |
| D9 | `argocd/charts/resource-groups/templates/krotest08-chained-orvalue-rg.yaml` | **ADD** | gen3-dev | KRO capability test RGD |
| D10 | `argocd/charts/resource-groups/Chart.yaml` | **MODIFY** | — | Update version to 0.2.0; update description to reflect both CSOC types |
| D11 | `argocd/charts/resource-groups/README.md` | **MODIFY** | — | Add capability test section from gen3-dev's README |
| D12 | `argocd/charts/resource-groups/values.yaml` | **NO-OP** | — | Empty; stays empty |
| D13 | `argocd/charts/application-sets/*` | **NO-OP** | — | Identical in both repos. Already supports the cluster generator pattern used by both bootstrap ApplicationSets. |
| D14 | `argocd/charts/instances/*` | **NO-OP** | — | Obsolete in both repos but not deleting in this merge. |
| D15 | `argocd/charts/cluster-resources/*` | **NO-OP** | — | gen3-kro only; untouched. |
| D16 | `argocd/charts/multi-acct/*` | **NO-OP** | — | gen3-kro only; untouched. |

---

## E) Cluster Fleet (`argocd/cluster-fleet/`)

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| E1 | `argocd/cluster-fleet/local-aws-dev/` (entire directory) | **ADD** | gen3-dev | The local CSOC fleet member directory |
| E1a | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-foundation.yaml` | **ADD** | gen3-dev | AwsGen3Foundation1 instance |
| E1b | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-database.yaml` | **ADD** | gen3-dev | AwsGen3Database1 instance |
| E1c | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-search.yaml` | **ADD** | gen3-dev | AwsGen3Search1 instance |
| E1d | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-compute.yaml` | **ADD** | gen3-dev | AwsGen3Compute2 instance |
| E1e | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-appiam.yaml` | **ADD** | gen3-dev | AwsGen3AppIAM1 instance |
| E1f | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-helm.yaml` | **ADD** | gen3-dev | AwsGen3Helm1 instance |
| E1g | `argocd/cluster-fleet/local-aws-dev/infrastructure/spoke1-observability.yaml` | **ADD** | gen3-dev | AwsGen3Observability1 instance |
| E1h | `argocd/cluster-fleet/local-aws-dev/tests/krotest01-foreach.yaml` | **ADD** | gen3-dev | Test instance |
| E1i | `argocd/cluster-fleet/local-aws-dev/tests/krotest02-includewhen.yaml` | **ADD** | gen3-dev | Test instance |
| E1j | `argocd/cluster-fleet/local-aws-dev/tests/krotest03-bridge-producer.yaml` | **ADD** | gen3-dev | Test instance |
| E1k | `argocd/cluster-fleet/local-aws-dev/tests/krotest04-bridge-consumer.yaml` | **ADD** | gen3-dev | Test instance |
| E1l | `argocd/cluster-fleet/local-aws-dev/tests/krotest05-cel.yaml` | **ADD** | gen3-dev | Test instance |
| E1m | `argocd/cluster-fleet/local-aws-dev/tests/krotest06-sg-conditional.yaml` | **ADD** | gen3-dev | Test instance |
| E1n | `argocd/cluster-fleet/local-aws-dev/tests/krotest07a-cross-rgd-producer.yaml` | **ADD** | gen3-dev | Test instance |
| E1o | `argocd/cluster-fleet/local-aws-dev/tests/krotest07b-cross-rgd-consumer.yaml` | **ADD** | gen3-dev | Test instance |
| E1p | `argocd/cluster-fleet/local-aws-dev/tests/krotest08-chained-orvalue.yaml` | **ADD** | gen3-dev | Test instance |
| E1q | `argocd/cluster-fleet/local-aws-dev/cluster-resources/app.yaml` | **ADD** | gen3-dev | Cluster registration |
| E1r | `argocd/cluster-fleet/local-aws-dev/cluster-resources/cluster-values.yaml` | **ADD** | gen3-dev | Cluster values |
| E1s | `argocd/cluster-fleet/local-aws-dev/spoke1.rds-pla.net/values.yaml` | **ADD** | gen3-dev | Spoke-specific overrides |
| E2 | `argocd/cluster-fleet/spoke1/*` | **NO-OP** | — | Untouched. EKS spoke stays as-is. |
| E3 | `argocd/cluster-fleet/_example/*` | **MODIFY** | — | Update README to document both local-aws-dev and spoke conventions |

---

## F) Dockerfile & DevContainer

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| F1 | `Dockerfile` | **MODIFY** | — | Add optional Kind binary install (behind a build ARG `INSTALL_KIND=false`). Default off — EKS users don't need Kind. |
| F2 | `.devcontainer/devcontainer.json` | **MODIFY** | — | Add `~/.gen3-dev` mount (conditional via comment or second devcontainer profile). EKS profile unchanged. |
| F3 | `.devcontainer/devcontainer-local.json` | **ADD** | gen3-dev | Separate devcontainer config for local CSOC workflow (mounts `~/.gen3-dev`, sets `KIND_CLUSTER_NAME`, `KUBECONFIG`) |

---

## G) Documentation & Instructions

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| G1 | `.github/copilot-instructions.md` | **ADD** or **MODIFY** | gen3-dev | If gen3-kro has one: merge local CSOC sections. If not: add it. |
| G2 | `.github/instructions/argocd.instructions.md` | **ADD** | gen3-dev | ArgoCD conventions for local CSOC |
| G3 | `.github/instructions/kro-rgd.instructions.md` | **ADD** | gen3-dev | KRO RGD conventions |
| G4 | `.github/instructions/local-testing.instructions.md` | **ADD** | gen3-dev | Kind testing conventions |
| G5 | `.github/instructions/scripts.instructions.md` | **ADD** | gen3-dev | Shell scripting conventions |
| G6 | `.github/instructions/dockerfile.instructions.md` | **ADD** | gen3-dev | Dockerfile conventions |
| G7 | `docs/local-csoc-guide.md` | **ADD** | new | Developer guide for the local CSOC workflow |
| G8 | `docs/architecture.md` | **MODIFY** | — | Add local CSOC section |
| G9 | `docs/deployment-guide.md` | **MODIFY** | — | Add Phase 0.5: Local CSOC Development |
| G10 | `CONTRIBUTING.md` | **MODIFY** | — | Add local CSOC development workflow |
| G11 | `README.md` | **MODIFY** | — | Add local CSOC quick-start section |

---

## H) Design Reports & Outputs

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| H1 | `docs/design-reports/03-kro-capability-test-report.md` | **ADD** | gen3-dev `outputs/design-reports/03-*` | Capability test results |
| H2 | `docs/design-reports/04-modular-sg-routetable-design.md` | **MODIFY** | — | Already exists in gen3-kro; verify parity with gen3-dev version |
| H3 | `docs/design-reports/05-rgd-update-behavior-test-report.md` | **ADD** | gen3-dev `outputs/design-reports/05-*` | RGD update behavior test |

---

## I) Gitignore & Config

| # | File | Action | Source | Notes |
|---|------|--------|--------|-------|
| I1 | `.gitignore` | **MODIFY** | — | Add `config/local.env`, `outputs/logs/kind-*`, `~/.gen3-dev/` patterns if not present |
| I2 | `.helmignore` | **NO-OP** | — | Already present |

---

## Summary Counts

| Action | Count |
|--------|-------|
| **ADD** | ~40 files |
| **MODIFY** | ~12 files |
| **RENAME** | 2 keys (`kro-eks-rgs` → `kro-csoc-rgs`, `kro-local-rgs` → `kro-csoc-rgs`) |
| **DELETE** | 0 files |
| **NO-OP** | ~25 files |
