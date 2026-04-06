# Merge Plan — Complete ✅

## All Phases Done

The gen3-dev → gen3-kro merge is fully implemented. gen3-kro now supports
**both** workflows from a single repository:

| Workflow | Cluster | Credentials | Orchestrator |
|----------|---------|-------------|--------------|
| **EKS CSOC** (production) | EKS on AWS | IRSA via Terraform | `container-init.sh` → `install.sh` (DevContainer) |
| **Local CSOC** (development) | Kind on host | K8s Secret (MFA-assumed-role) | `kind-local-test.sh` (host shell — no container) |

After the merge, gen3-dev becomes obsolete. Developers clone gen3-kro and
choose their workflow.

---

## Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Rename `kro-eks-rgs` → `kro-csoc-rgs` | ✅ Complete |
| Phase 2 | Scripts: kind-config.yaml, kind-local-test.sh, kro-status-report.sh | ✅ Complete |
| Phase 3 | Local addons + bootstrap + csoc-addons parameterization | ✅ Complete |
| Phase 4 | Cluster fleet (local-aws-dev) + 9 test RGDs + Chart.yaml 0.2.0 | ✅ Complete |
| Phase 5 | DevContainer: add `chat.instructionsFilesLocations` to devcontainer.json | ✅ Complete |
| Phase 6 (Terraform) | `addons_config_path` in aws-csoc locals.tf | ✅ Complete |
| Phase 6 (Docs) | `.github/`, `docs/`, README, CONTRIBUTING, .gitignore | ✅ Complete |

> **Revised**: Phase 5 no longer includes Dockerfile changes or
> `devcontainer-local.json`. Local Kind CSOC runs on the host — no container.



---

## User Decisions (locked in)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **`~/.aws` is NOT a direct target** — credential paths remain `~/.aws/eks-devcontainer` for the container and `~/.aws/credentials` for host usage. No script should read from or write to `~/.aws` directly. | Security isolation; keeps mfa-session.sh's credential output directory unchanged |
| 2 | **Rename `kro-local-rgs` → `kro-csoc-rgs`** everywhere (both the local addons and the EKS `kro-eks-rgs` key converge to `kro-csoc-rgs`) | Unified naming — one CSOC, two runtimes |
| 3 | **Credential logic stays separate** — `container-init.sh` handles EKS CSOC creds (IRSA + Terraform); `kind-local-test.sh` handles local CSOC creds (K8s Secret injection). No need to merge credential functions. | Minimal complexity; each path already works; integration is at the ArgoCD/bootstrap level |

---

## Plan Documents

| Document | Purpose |
|----------|---------|
| [01-file-inventory.md](01-file-inventory.md) | Every file to add, modify, rename, or delete in gen3-kro |
| [02-argocd-integration.md](02-argocd-integration.md) | ArgoCD addons, bootstrap, and application-sets changes |
| [03-scripts-integration.md](03-scripts-integration.md) | Scripts to bring over, modify, or share |
| [04-dockerfile-devcontainer.md](04-dockerfile-devcontainer.md) | Dockerfile and devcontainer.json changes |
| [05-cluster-fleet-tests.md](05-cluster-fleet-tests.md) | Cluster fleet directories, test RGDs, and instance files |
| [06-documentation-updates.md](06-documentation-updates.md) | Docs, instructions, copilot-instructions, CONTRIBUTING |
| [07-implementation-sequence.md](07-implementation-sequence.md) | Ordered task list with dependencies |
| [08-validation-checklist.md](08-validation-checklist.md) | How to verify the merge is complete and correct |

---

## Principles

1. **No code duplication** — shared logic (logging, credential tiers, RGDs) exists once.
2. **No breaking changes** — existing EKS CSOC workflow (`container-init.sh setup init apply connect`) is untouched.
3. **Additive** — local CSOC is a new capability, not a replacement.
4. **Convention parity** — same sync-wave ordering, bridge patterns, annotation patterns, naming conventions.
5. **Credential isolation** — each workflow manages its own credential pipeline independently.
