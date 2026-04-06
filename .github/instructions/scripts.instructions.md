---
applyTo: "scripts/**"
---

# Shell Script Conventions

These rules apply when creating or editing scripts in `scripts/`.

## Error Handling

Every script must start with:
```bash
set -euo pipefail
```

## Logging

Scripts use **inline logging helpers** (no shared lib-logging.sh dependency).
Copy the inline block from an existing script (e.g., `kind-local-test.sh`):

```bash
# ── Logging helpers (inline — no lib-logging.sh dependency) ─────────────────
log_info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
log_stage()   { echo -e "\n\033[1;36m══ $* ══\033[0m"; }
```

## Script Roles

| Script | Workflow | Purpose |
|--------|----------|---------|
| `install.sh` | EKS CSOC | Terraform init + apply (CSOC cluster + ArgoCD) |
| `destroy.sh` | EKS CSOC | Terraform destroy |
| `container-init.sh` | EKS CSOC | DevContainer entrypoint — runs on container start |
| `mfa-session.sh` | Both | Assumes MFA role, writes `~/.aws` credentials |
| `kind-local-test.sh` | Local CSOC | Full Kind cluster lifecycle (create/install/inject-creds/delete) |
| `kro-status-report.sh` | Local CSOC | Human-readable KRO/ACK status snapshot |
| `namespace-infra-report.sh` | Local CSOC | Namespace-scoped infrastructure summary |

## Flag-Based Orchestration (Local CSOC)

`kind-local-test.sh` uses positional flags to select stages.
This mirrors the container-init.sh pattern:

```bash
for arg in "$@"; do
  case "${arg}" in
    create)       FLAG_CREATE=true ;;
    install)      FLAG_INSTALL=true ;;
    inject-creds) FLAG_INJECT=true ;;
    delete)       FLAG_DELETE=true ;;
  esac
done
```

When adding new stages, follow this pattern — don't switch to getopts.

## container-init.sh (EKS CSOC)

This script runs automatically when the DevContainer starts. It:
- Sources MFA credentials from `~/.aws/eks-devcontainer/credentials`
- Configures kubeconfig for the CSOC EKS cluster
- Starts any required port-forwards

Do **not** add local CSOC logic to `container-init.sh`. Local CSOC is
host-only and does not use the DevContainer.

## Variable Quoting

Always quote variables to prevent word splitting:
```bash
"${CLUSTER_NAME}"   # ✓
$CLUSTER_NAME        # ✗
```

## Script Paths

Use portable path resolution at the top of every script:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

## Helm Install Pattern (Local CSOC)

Wrap Helm installs with a consistent pattern:
```bash
helm upgrade --install <release> <chart_ref> \
  --namespace <namespace> \
  --create-namespace \
  --wait --timeout 5m \
  [extra args...]
```
