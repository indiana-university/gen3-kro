---
description: 'Shell script conventions, logging helpers, and orchestration patterns for gen3-kro scripts'
applyTo: "scripts/**"
---

# Shell Script Conventions

## Required Header

Every script must start with:
```bash
#!/usr/bin/env bash
set -euo pipefail
```

## Logging Helpers (inline — no external lib)

Copy this block verbatim into any new script:
```bash
# ── Logging helpers ──────────────────────────────────────────────────────────
log_info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
log_stage()   { echo -e "\n\033[1;36m══ $* ══\033[0m"; }
```

## Portable Path Resolution

Use this at the top of every script:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
```

## Variable Quoting

Always quote variables:
```bash
"${VAR}"    # correct
$VAR        # wrong
```

## Script Roles

| Script | Workflow | Purpose |
|--------|----------|---------|
| `install.sh` | EKS CSOC | Terraform init + apply (CSOC cluster + ArgoCD) |
| `destroy.sh` | EKS CSOC | Terraform destroy |
| `container-init.sh` | EKS CSOC | DevContainer entrypoint — runs on container start |
| `mfa-session.sh` | Both | Assumes MFA role, writes `~/.aws` credentials |
| `kind-local-test.sh` | Local CSOC | Full Kind cluster lifecycle |
| `kro-status-report.sh` | Local CSOC | Human-readable KRO/ACK status snapshot |
| `namespace-infra-report.sh` | Local CSOC | Namespace-scoped infrastructure summary |

## Flag-Based Orchestration (`kind-local-test.sh`)

Uses positional flags (not getopts):
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

When adding new stages, follow this pattern — do not switch to getopts.

## Helm Install Pattern

```bash
helm upgrade --install <release> <chart_ref> \
  --namespace <namespace> \
  --create-namespace \
  --wait --timeout 5m \
  [extra args...]
```

## container-init.sh (EKS CSOC)

Runs automatically at DevContainer start. It:
- Sources MFA credentials from `~/.aws/eks-devcontainer/credentials`
- Configures kubeconfig for the CSOC EKS cluster

Do **not** add local CSOC logic to `container-init.sh`.
