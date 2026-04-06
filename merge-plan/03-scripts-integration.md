# 03 — Scripts Integration ✅ Complete

> All work in this plan is implemented. This file is retained for reference.
>
> **Implemented**:
> - `scripts/kind-config.yaml` — added (Kind cluster config, NodePort 30080)
> - `scripts/kind-local-test.sh` — added (~560 lines, gen3-kro URL, inline logging)
> - `scripts/kro-status-report.sh` — added (~350 lines, inline logging, 5 sections)

---

<!-- Original plan content below (reference only) -->

# 03 — Scripts Integration Plan (ORIGINAL)

Covers: shell scripts to add, modify, or share between EKS and local workflows.

---

## 1. Scripts Inventory

### gen3-dev (local CSOC) — to bring into gen3-kro

| File | Size | Purpose | Action |
|------|------|---------|--------|
| `kind-local-test.sh` | ~700 lines | Flag-based Kind orchestration (create/install/inject-creds/connect/test/status/destroy/setup) | ADD with modifications |
| `kind-config.yaml` | ~25 lines | Kind cluster config (port mappings, apiServer settings) | ADD as-is |
| `kro-status-report.sh` | ~200+ lines | KRO + ACK status report with filtering flags | ADD with modifications |

### gen3-kro (EKS CSOC) — already present, no changes

| File | Purpose | Action |
|------|---------|--------|
| `container-init.sh` | Flag-based EKS orchestration (setup/init/apply/connect) | NO-OP |
| `install.sh` | Terraform init/apply/destroy wrapper | NO-OP |
| `destroy.sh` | Terraform destroy + cleanup | NO-OP |
| `mfa-session.sh` | AWS MFA credential renewal | NO-OP |
| `namespace-infra-report.sh` | Per-spoke resource inventory | NO-OP |
| `ssm-repo-secrets/` | SSM secret management scripts | NO-OP |

---

## 2. `kind-local-test.sh` — Required Modifications

### 2a. Git Repository Constants

```bash
# BEFORE (gen3-dev)
GIT_REPO_URL="https://github.com/jayadeyemi/gen3-dev.git"
GIT_REPO_REVISION="main"
GIT_REPO_BASEPATH="argocd/"

# AFTER (in gen3-kro)
GIT_REPO_URL="https://github.com/indiana-university/gen3-kro.git"
GIT_REPO_REVISION="main"
GIT_REPO_BASEPATH="argocd/"
```

The `GIT_REPO_URL` is the most critical change — it controls the ArgoCD cluster
Secret's `addons_repo_url` annotation, which tells ArgoCD where to pull charts
and addons. After merge, the local Kind cluster pulls from gen3-kro.

### 2b. Script Header Comment

Update the header to reflect gen3-kro:

```bash
# BEFORE
# Kind Local CSOC — Flag-based Orchestration for gen3-dev

# AFTER
# Kind Local CSOC — Flag-based Orchestration (gen3-kro)
```

### 2c. Addons File Reference

The `kro-status-report.sh` references addons path — verify after copy:

```bash
# kro-status-report.sh references:
ADDONS_FILE="${REPO_DIR}/argocd/addons/local/addons.yaml"
INFRA_DIR="${REPO_DIR}/argocd/cluster-fleet/local-aws-dev"
```

These paths are already repo-relative and will work in gen3-kro since
`addons/local/` and `cluster-fleet/local-aws-dev/` are being added.

### 2d. ACK Controller Versions

The `ACK_CONTROLLERS` associative array in `kind-local-test.sh` lists controller
names + versions used in the inject-creds stage. These versions are **not** the
chart versions from addons.yaml — they are the ACK controller deployment names
used for `kubectl set env`. The versions in this array may be stale and should
be reviewed, but they serve as deployment-name pattern matching, not version
pinning.

```bash
declare -A ACK_CONTROLLERS=(
  [ec2]="1.9.2"      # Used for: ack-ec2-controller deployment name
  [eks]="1.11.1"
  ...
)
```

**Decision needed**: These version strings appear in the inject-creds stage
when patching. Verify they match the actual deployed controller versions.
The inject-creds function likely uses them for naming, not version enforcement.

### 2e. Bootstrap ApplicationSet References

`kind-local-test.sh` applies bootstrap ApplicationSets by name in `stage_install()`:

```bash
kubectl apply -f "${REPO_DIR}/argocd/bootstrap/csoc-addons.yaml"
kubectl apply -f "${REPO_DIR}/argocd/bootstrap/local-infra-instances.yaml"
```

`csoc-addons.yaml` already exists in gen3-kro and is being modified to use the
`addons_config_path` cluster annotation (see plan 02). `local-infra-instances.yaml`
is added from gen3-dev. Both paths are repo-relative and will work.

---

## 3. `lib-logging.sh` — NOT Brought Over

`lib-logging.sh` is not added to gen3-kro. Both `kind-local-test.sh` and
`kro-status-report.sh` must embed their logging functions inline, matching the
pattern already used by `container-init.sh`.

Required modifications when copying each script:
- Remove `source "${SCRIPT_DIR}/lib-logging.sh"` line
- Add an inline logging block at the top of the script:

```bash
# ── Logging helpers ───────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  _CLR_RST='\033[0m'; _CLR_GRN='\033[0;32m'; _CLR_YLW='\033[0;33m'
  _CLR_RED='\033[0;31m'; _CLR_BLU='\033[0;34m'; _CLR_CYN='\033[0;36m'
else
  _CLR_RST='' _CLR_GRN='' _CLR_YLW='' _CLR_RED='' _CLR_BLU='' _CLR_CYN=''
fi
log_info()    { echo -e "${_CLR_BLU}  \u2139${_CLR_RST} $*"; }
log_success() { echo -e "${_CLR_GRN}  \u2713${_CLR_RST} $*"; }
log_warn()    { echo -e "${_CLR_YLW}  \u26a0${_CLR_RST} $*" >&2; }
log_error()   { echo -e "${_CLR_RED}  \u2717${_CLR_RST} $*" >&2; }
log_stage()   { echo -e "\n${_CLR_CYN}>>> [$1]${_CLR_RST} $2"; }
log_banner()  {
  echo ""
  echo "\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501"
  echo "  $*"
  echo "\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501"
}
```

This is the same ANSI-colour pattern already in lib-logging.sh; extracting it
inline keeps each script self-contained with no runtime dependency.

---

## 4. `kind-config.yaml` — Add As-Is

Kind cluster configuration: control-plane node with port mappings (30080 for
ArgoCD NodePort) and apiServer timeout override.

**No modifications needed.**

---

## 5. `kro-status-report.sh` — Required Modifications

### 5a. Header Comment

```bash
# BEFORE
# kro-status-report.sh — KRO + ACK Resource Status Report for gen3-dev

# AFTER
# kro-status-report.sh — KRO + ACK Resource Status Report (Local CSOC)
```

### 5b. Addons File Path

Already references `argocd/addons/local/addons.yaml` — correct for gen3-kro
since that file is being added at the same path.

### 5c. Cluster Fleet Path

Already references `argocd/cluster-fleet/local-aws-dev` — correct.

---

## 6. Credential Logic — Stays Separate (User Decision #3)

Both `kind-local-test.sh` and `container-init.sh` contain `validate_credentials()`
functions that are structurally similar but intentionally different:

| Aspect | `kind-local-test.sh` (local) | `container-init.sh` (EKS) |
|--------|------------------------------|---------------------------|
| Credential source | `${HOME}/.aws/credentials` | `/home/vscode/.aws/credentials` |
| Logging | Inline logging functions | Inline echo |
| MFA script reference | `scripts/mfa-session.sh` on HOST | `scripts/mfa-session.sh` on HOST |
| Tier system | Same 4-tier model | Same 4-tier model |
| Injection method | `kubectl create secret` + `kubectl set env` | IRSA (no injection needed) |

**No refactoring**. The parallel implementations are acceptable complexity given
the fundamentally different credential delivery mechanisms (K8s Secret vs. IRSA).

---

## 7. Relationship Between Scripts

After merge, `gen3-kro/scripts/` will contain:

```
scripts/
├── container-init.sh           # EKS CSOC orchestration (existing)
├── install.sh                  # Terraform wrapper (existing)
├── destroy.sh                  # Terraform destroy (existing)
├── mfa-session.sh              # MFA credential renewal (existing)
├── namespace-infra-report.sh   # Per-spoke resource report (existing)
├── ssm-repo-secrets/           # SSM scripts (existing)
├── kind-local-test.sh          # Local CSOC orchestration (NEW — inline logging)
├── kind-config.yaml            # Kind cluster config (NEW)
└── kro-status-report.sh        # KRO status report (NEW — inline logging)
```

The two orchestration scripts are **mutually exclusive workflows**:
- `container-init.sh` → EKS CSOC (runs as devcontainer postCreateCommand)
- `kind-local-test.sh` → Local CSOC (runs manually by developer)

They never call each other. `lib-logging.sh` is used only by the local scripts.

