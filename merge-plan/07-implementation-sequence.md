# 07 — Implementation Sequence ✅ Complete

## Documentation & GitHub Instructions — ✅ Done

All documentation tasks have been implemented.

### Priority 1 — `.github/` (enables Copilot context immediately)

| # | Task | File | Notes |
|---|------|------|-------|
| D1 | Create `.github/copilot-instructions.md` | NEW | Always-on Copilot context for EKS + local CSOC; based on gen3-dev version but expanded for gen3-kro specifics (Terraform, IRSA, Terragrunt, spoke mgmt) |
| D2 | Create `.github/instructions/argocd.instructions.md` | NEW | Port from gen3-dev + update for both CSOC modes |
| D3 | Create `.github/instructions/kro-rgd.instructions.md` | NEW | Port from gen3-dev (mostly repo-agnostic) |
| D4 | Create `.github/instructions/local-testing.instructions.md` | NEW | Port from gen3-dev + update to "host-based, no container" |
| D5 | Create `.github/instructions/scripts.instructions.md` | NEW | Port from gen3-dev + note `container-init.sh` for EKS |
| D6 | Create `.github/instructions/dockerfile.instructions.md` | NEW | Port from gen3-dev, update INSTALL_KIND section |

### Priority 2 — `.gitignore`

| # | Task | File | Notes |
|---|------|------|-------|
| D7 | Remove `.github/**` ignore line | `.gitignore` | This line prevents the instructions files from being tracked; confirm it exists first |

### Priority 3 — Docs

| # | Task | File | Notes |
|---|------|------|-------|
| D8 | Create `docs/local-csoc-guide.md` | NEW | Host prerequisites (Kind, AWS creds), kind-local-test.sh stage walkthrough, credential injection |
| D9 | Modify `docs/architecture.md` | MODIFY | Add "Local CSOC" section |
| D10 | Modify `docs/deployment-guide.md` | MODIFY | Add local CSOC setup section (host-based) |
| D11 | Modify `CONTRIBUTING.md` | MODIFY | Add local CSOC development workflow |
| D12 | Modify `README.md` | MODIFY | Add dual-workflow quick-start |

### Priority 4 — Design Reports

| # | Task | File | Notes |
|---|------|------|-------|
| D13 | Add capability test report | `docs/design-reports/03-kro-capability-test-report.md` | Copy from gen3-dev `outputs/design-reports/` |
| D14 | Add update behavior report | `docs/design-reports/05-rgd-update-behavior-test-report.md` | Copy from gen3-dev `outputs/design-reports/` |

---

## Dependency Graph

```
D7 (.gitignore remove .github/**)
    │
    ↓
D1–D6 (.github/ instruction files  — Copilot picks them up once .gitignore is fixed)
    │
    ↓
D8–D12 (docs + README + CONTRIBUTING — reference .github/ files)
    │
    ↓
D13–D14 (design reports — standalone, no deps)
```

---

## Validation (Post-Phase 6)

- [ ] `git ls-files .github/` shows all 6 instruction files (not ignored)
- [ ] Copilot context panel loads `argocd.instructions.md` when editing `argocd/**`
- [ ] `docs/local-csoc-guide.md` covers all host prerequisites
- [ ] `README.md` has a "Local CSOC" quick-start section
- [ ] No gen3-dev references remain in the new files

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 0.1 | Review and approve this merge plan | — | User picks options (e.g., test RGD guard pattern) |
| 0.2 | Create a feature branch in gen3-kro | — | `feature/local-csoc-merge` or similar |
| 0.3 | Verify gen3-dev and gen3-kro are in sync | — | Confirm production RGDs are identical |

---

## Phase 1: Rename `kro-eks-rgs` → `kro-csoc-rgs` (EKS Side)

This is the **highest-risk change** since it affects the running EKS CSOC.
Do it first, alone, so failures are isolated and easy to roll back.

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 1.1 | Rename key in `argocd/addons/csoc/addons.yaml` | 0.2 | `kro-eks-rgs` → `kro-csoc-rgs` |
| 1.2 | Rename selector key `enable_kro_eks_rgs` → `enable_kro_csoc_rgs` | 1.1 | In the same addons.yaml |
| 1.3 | Search Terraform for `enable_kro_eks_rgs` and update | 1.2 | Cluster secret labels in ArgoCD bootstrap module |
| 1.4 | Validate: ArgoCD still reconciles RGDs on EKS | 1.3 | Check ArgoCD UI / `argocd app list` |

**Rollback**: Revert the key rename in addons.yaml.

---

## Phase 2: Add Scripts

No dependencies on Phase 1 (can start in parallel on the branch, but merge
after Phase 1 to keep PR history clean).

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 2.1 | Add `scripts/kind-config.yaml` | 0.2 | Copy as-is from gen3-dev |
| 2.2 | Add `scripts/kind-local-test.sh` | 0.2 | Copy from gen3-dev + update `GIT_REPO_URL`, header comment; embed logging inline |
| 2.3 | Add `scripts/kro-status-report.sh` | 0.2 | Copy from gen3-dev + update header comment; embed logging inline |

---

## Phase 3: Add Local Addons & Bootstrap

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 3.1 | Create `argocd/addons/local/` directory | 0.2 | — |
| 3.2 | Add `argocd/addons/local/addons.yaml` | 3.1 | Copy from gen3-dev + rename `kro-local-rgs` → `kro-csoc-rgs` |
| 3.3 | Modify `argocd/bootstrap/csoc-addons.yaml` | 0.2 | Parameterize `valueFiles` via `addons_config_path` cluster annotation |
| 3.4 | Update Terraform bootstrap module | 3.3 | Set `addons_config_path: argocd/addons/csoc/addons.yaml` on EKS cluster secrets |
| 3.5 | Add `argocd/bootstrap/local-infra-instances.yaml` | 0.2 | Copy as-is from gen3-dev |

---

## Phase 4: Add Test RGDs & Cluster Fleet

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 4.1 | Add 9 test RGD files to `charts/resource-groups/templates/` | 0.2 | Copy from gen3-dev |
| 4.2 | Bump `charts/resource-groups/Chart.yaml` version | 4.1 | 0.1.0 → 0.2.0 |
| 4.3 | Update `charts/resource-groups/README.md` | 4.1 | Document test RGDs |
| 4.4 | Add entire `cluster-fleet/local-aws-dev/` tree | 3.5 | Copy from gen3-dev (19 files) |

---

## Phase 5: Dockerfile & DevContainer

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 5.1 | Modify `Dockerfile` — add KIND_VERSION + INSTALL_KIND ARGs | 0.2 | Conditional Kind install block |
| 5.2 | Add `.devcontainer/devcontainer-local.json` | 5.1 | New devcontainer for local CSOC |
| 5.3 | Modify `.devcontainer/devcontainer.json` (minor) | 0.2 | Add `chat.instructionsFilesLocations` if missing |

---

## Phase 6: Documentation

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 6.1 | Create `.github/copilot-instructions.md` | All above | Describes both workflows |
| 6.2 | Add 5 instruction files to `.github/instructions/` | 6.1 | Copy from gen3-dev + modify |
| 6.3 | Add 2 design reports to `docs/design-reports/` | 0.2 | 03-kro-capability-test-report, gen3-platform-research-report |
| 6.4 | Update `docs/deployment-guide.md` | 2.3, 5.2 | Add local CSOC section |
| 6.5 | Update `docs/architecture.md` | 3.2 | Add local CSOC architecture |
| 6.6 | Update `docs/security.md` | 2.3 | Add credential injection docs |
| 6.7 | Update `README.md` | All above | Add dual-workflow section |
| 6.8 | Update `CONTRIBUTING.md` | 0.2 | Add local development workflow |
| 6.9 | Update `.gitignore` | 0.2 | Add local CSOC patterns |

---

## Phase 7: Validation

| # | Task | Depends On | Notes |
|---|------|-----------|-------|
| 7.1 | EKS CSOC sanity check | Phase 1 | ArgoCD apps reconcile with renamed kro-csoc-rgs |
| 7.2 | Build Docker image (default — no Kind) | Phase 5 | `docker build -t gen3-kro .` |
| 7.3 | Build Docker image (local — with Kind) | Phase 5 | `docker build --build-arg INSTALL_KIND=true .` |
| 7.4 | Local CSOC end-to-end test | Phases 2-5 | `kind-local-test.sh create install inject-creds connect test` |
| 7.5 | Run kro-status-report.sh | 7.4 | Verify all RGDs and test instances |
| 7.6 | Code review + merge PR | All above | — |

---

## Dependency Graph (simplified)

```
Phase 0 (prep)
    │
    ├── Phase 1 (rename kro-eks-rgs → kro-csoc-rgs)
    │       │
    │       └── Phase 7.1 (EKS sanity check)
    │
    ├── Phase 2 (scripts) ─────────────┐
    │                                   │
    ├── Phase 3 (addons + bootstrap) ──├── Phase 4 (RGDs + fleet)
    │                                   │
    └── Phase 5 (Dockerfile + DC) ─────┘
                                        │
                                   Phase 6 (docs)
                                        │
                                   Phase 7 (validation)
```

---

## Estimated Change Summary

| Metric | Count |
|--------|-------|
| New files | ~39 |
| Modified files | ~12 |
| Renamed keys | 2 (`kro-eks-rgs`, `kro-local-rgs` → `kro-csoc-rgs`) |
| Deleted files | 0 |
| PRs recommended | 1-3 (Phase 1 alone + Phases 2-6 together + Phase 7) |
