# 06 — Documentation Plan ✅ Complete

## 1. `.gitignore` ✅

Remove the line `.github/**` (or equivalent pattern that blocks `.github/` from git tracking). This unblocks Copilot from loading instruction files.

Verify: `grep -n 'github' .gitignore`

---

## 2. `.github/copilot-instructions.md` (Always-On Context)

Create a new file. Use gen3-dev's `copilot-instructions.md` as a template but expand it to cover gen3-kro specifics:

- **Both workflows**: EKS CSOC (primary) and Local CSOC (host-based)
- **Technology stack**: Terraform, Terragrunt, KRO, ACK, ArgoCD, Kind
- **Directory layout**: merged layout with both EKS and local paths
- **Credential patterns**: IRSA for EKS, K8s Secret injection for local
- **RGD tiers**: modular architecture (Foundation → Database → Search → Compute → AppIAM → Helm → Observability)
- **Capability tests**: 8 test RGDs and what they validate
- **Security rules**: never commit secrets, account IDs, ARNs
- **Key name**: `kro-csoc-rgs` (not eks-rgs or local-rgs)

---

## 3. `.github/instructions/` (Targeted Instruction Files)

Port all 5 from gen3-dev. Changes needed per file:

| File | Port From gen3-dev | Changes Required |
|------|--------------------|------------------|
| `argocd.instructions.md` | Yes | Update repo references gen3-dev → gen3-kro; mention both CSOC addon files |
| `kro-rgd.instructions.md` | Yes | Minimal — mostly repo-agnostic; verify RGD naming conventions match |
| `local-testing.instructions.md` | Yes | Update to host-based (no container); update repo URL |
| `scripts.instructions.md` | Yes | Add note about `container-init.sh` for EKS; no `lib-logging.sh` — inline logging |
| `dockerfile.instructions.md` | Yes | Remove INSTALL_KIND content; EKS-only container; note local CSOC is host-only |

---

## 4. Docs

| File | What to Add |
|------|-------------|
| `docs/local-csoc-guide.md` | **NEW** — host prerequisites (Kind, MFA creds), `kind-local-test.sh` stage walkthrough (create/install/inject-creds/connect/test/destroy), credential injection detail |
| `docs/architecture.md` | Add "Local CSOC" section: Kind on host, credential injection via K8s Secret, same ArgoCD bootstrap chain as EKS |
| `docs/deployment-guide.md` | Add local CSOC setup section: prerequisites, `kind-local-test.sh` commands, no container needed |
| `docs/security.md` | Add K8s Secret credential injection pattern vs IRSA; note `inject-creds` stage |

---

## 5. Root Files

**`README.md`** — Add dual-workflow section:

```markdown
## Workflows

### EKS CSOC (Production)
- DevContainer with Terraform/Terragrunt
- `container-init.sh setup init apply connect`
- Manages EKS cluster + spoke accounts via IRSA

### Local CSOC (Development/Testing)
- Runs directly on host (no container)
- `bash scripts/kind-local-test.sh create install inject-creds connect`
- Kind cluster on host managing real AWS resources via credential injection
```

**`CONTRIBUTING.md`** — Add local CSOC development section:
- Prerequisites: Kind on host, MFA session, `~/.aws/credentials` with `[csoc]` profile
- Commands: `kind-local-test.sh create install inject-creds connect test`
- How to add new test RGDs
- Inline logging conventions (no lib-logging.sh)

---

## 6. Design Reports to Copy

| Source (gen3-dev) | Destination (gen3-kro) |
|-------------------|------------------------|
| `outputs/design-reports/03-kro-capability-test-report.md` | `docs/design-reports/03-kro-capability-test-report.md` |
| `outputs/design-reports/05-rgd-update-behavior-test-report.md` | `docs/design-reports/05-rgd-update-behavior-test-report.md` |


---

## 1. Copilot Instruction Files (`.github/instructions/`)

gen3-dev has 5 targeted instruction files. gen3-kro has no `.github/` directory
at all (its `copilot-instructions.md` lives somewhere else or doesn't exist yet).

### Files to Add

| File | Purpose | Modifications Needed |
|------|---------|---------------------|
| `argocd.instructions.md` | ArgoCD patterns, sync-waves, addon structure | Update references from gen3-dev → gen3-kro; mention both CSOC modes |
| `kro-rgd.instructions.md` | KRO DSL patterns, readyWhen/includeWhen, RGD naming | Minimal — already repo-agnostic |
| `local-testing.instructions.md` | Local CSOC workflow, kind-local-test.sh usage | Update repo references |
| `scripts.instructions.md` | Shell script conventions, lib-logging.sh usage | Add notes about container-init.sh (EKS) |
| `dockerfile.instructions.md` | Dockerfile conventions, build args | Add INSTALL_KIND documentation |

### Target Path

```
.github/
├── copilot-instructions.md        # ADD or MODIFY (see below)
└── instructions/
    ├── argocd.instructions.md     # ADD
    ├── kro-rgd.instructions.md    # ADD
    ├── local-testing.instructions.md   # ADD
    ├── scripts.instructions.md    # ADD
    └── dockerfile.instructions.md # ADD
```

---

## 2. `copilot-instructions.md` (Always-On)

### Current State

- gen3-dev: Has a comprehensive `copilot-instructions.md` in `.github/`
- gen3-kro: Does not have a `.github/copilot-instructions.md`

### Strategy

Create a **new** `.github/copilot-instructions.md` for gen3-kro that:

1. **Describes BOTH workflows** — EKS CSOC (primary) and Local CSOC
2. **Includes the technology stack** — Terraform, Terragrunt, KRO, ACK, ArgoCD, Kind
3. **Documents the directory layout** — merged layout with both EKS and local paths
4. **References the kro-csoc-rgs rename** — use `kro-csoc-rgs` throughout
5. **Includes credential patterns** for both modes (IRSA for EKS, K8s Secret for local)
6. **Lists RGD tiers** (modular architecture) and capability tests
7. **Security rules** — same "never commit secrets" guidelines

The gen3-dev copilot-instructions.md serves as a template but must be
significantly expanded to cover the EKS workflow (Terraform, multi-account,
IRSA, spoke management).

---

## 3. Design Reports

### Reports in gen3-dev that are missing from gen3-kro

| Report | gen3-dev path | gen3-kro path | Action |
|--------|--------------|--------------|--------|
| `03-kro-capability-test-report.md` | `outputs/design-reports/` | `docs/design-reports/` | ADD (copy, adjust path references) |
| `gen3-platform-research-report.md` | `outputs/design-reports/` | `docs/design-reports/` | ADD (copy) |

### Reports already in both repos

| Report | gen3-dev | gen3-kro | Action |
|--------|----------|----------|--------|
| `01-gen3-infrastructure-component-map.md` | ✓ | ✓ | NO-OP (verify parity) |
| `02-modular-rgd-design.md` | ✓ | ✓ | NO-OP (verify parity) |
| `04-modular-sg-routetable-design.md` | ✓ | ✓ | NO-OP (verify parity) |
| `05-rgd-update-behavior-test-report.md` | ✓ | ✓ | NO-OP (verify parity) |

### Reports unique to gen3-kro

| Report | gen3-kro path | Action |
|--------|--------------|--------|
| `gen3-application-report.md` | `docs/design-reports/` | NO-OP (gen3-kro only) |

### Note on Path Difference

gen3-dev stores reports in `outputs/design-reports/`.
gen3-kro stores reports in `docs/design-reports/`.
When copying, files go into `docs/design-reports/`.

---

## 4. `docs/` Updates

### Existing Files to Modify

| File | Changes Needed |
|------|---------------|
| `docs/architecture.md` | Add section on "Local CSOC" mode alongside EKS CSOC architecture |
| `docs/deployment-guide.md` | Add "Local CSOC Setup" section — **host-based workflow** (Kind on host, no container); kind-local-test.sh stages, prerequisites |
| `docs/security.md` | Add notes on local credential injection pattern (K8s Secret vs. IRSA) |

> **Revised**: DevContainer section removed. Local CSOC uses host shell only.
> Document `kind-local-test.sh` as the entry point, not a devcontainer.

### New Files

| File | Purpose |
|------|---------|
| `docs/local-csoc-guide.md` | Comprehensive guide for local CSOC workflow (alternative: fold into deployment-guide.md) |

**Decision**: Whether to create a standalone local CSOC guide or add a section
to the existing deployment guide. Recommendation: add to `deployment-guide.md`
to avoid document sprawl.

---

## 5. Root Documentation

### `README.md`

**Action: MODIFY** — Add a section explaining the dual-workflow nature:

```markdown
## Workflows

### EKS CSOC (Production)
- DevContainer with Terraform/Terragrunt
- `container-init.sh setup init apply connect`
- Manages EKS cluster + spoke accounts via IRSA

### Local CSOC (Development/Testing)
- Runs directly on host (no container)
- `bash scripts/kind-local-test.sh create install inject-creds connect`
- Kind cluster on host managing real AWS resources via credential injection
```

### `CONTRIBUTING.md`

**Action: MODIFY** — Add section on local CSOC development workflow:
- Prerequisites: Kind on host, AWS MFA session, `~/.aws/credentials` with `[csoc]` profile
- How to run `kind-local-test.sh create install inject-creds connect`
- How to run tests via `kind-local-test.sh test`
- How to add new test RGDs
- Inline logging conventions (no lib-logging.sh)

---

## 6. `.gitignore` Updates

**Action: MODIFY** — Ensure gen3-kro's `.gitignore` covers local CSOC artifacts:

```gitignore
# Local CSOC
config/local.env
.gen3-dev/
```

Verify these patterns aren't already covered. `config/local.env` is likely
already gitignored. `.gen3-dev/` is a host-side directory and wouldn't appear
in the repo, but adding it is defensive.

---

## 7. Summary

| Category | Files to ADD | Files to MODIFY |
|----------|-------------|----------------|
| `.github/instructions/` | 5 instruction files | — |
| `.github/copilot-instructions.md` | 1 new file | — |
| `docs/design-reports/` | 2 reports | — |
| `docs/` | 0 | 3 (architecture, deployment-guide, security) |
| Root docs | 0 | 2 (README, CONTRIBUTING) |
| `.gitignore` | 0 | 1 |
| **Total** | **8** | **6** |
