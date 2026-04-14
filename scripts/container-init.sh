#!/usr/bin/env bash
###############################################################################
# Dev Container Init Script — Flag-based Orchestration (V2 — Plain Terraform)
#
# Runs as postCreateCommand. Each stage is opt-in via positional flags.
# With no flags, nothing runs (safe no-op).
#
# Usage:
#   bash container-init.sh                       # No-op
#   bash container-init.sh setup                 # Env setup only
#   bash container-init.sh setup init            # Env setup + terraform init
#   bash container-init.sh setup init apply      # Full pipeline
#   bash container-init.sh setup connect         # Env setup + connect to existing cluster
#   bash container-init.sh init apply            # Skip setup if already configured
#
# Stages:
#   setup   — dirs, script copies, AWS cred validation, env file, MCP, codex
#   init    — push SSM secrets + terraform init (via install.sh init)
#   apply   — terraform apply + connect to cluster (via install.sh apply)
#   connect — kubeconfig update + ArgoCD port-forward (no TF dependency)
#
# Configure in devcontainer.json → postCreateCommand:
#   "bash scripts/container-init.sh setup"            # Dev: env only
#   "bash scripts/container-init.sh setup init apply" # CI/Fresh: full pipeline
###############################################################################
set -euo pipefail

REPO_DIR="${REPO_ROOT:-/workspaces/eks-cluster-mgmt}"
ENV_DIR="${REPO_DIR}/terraform/env/aws/csoc-cluster"
OUTPUTS_DIR="${REPO_DIR}/outputs"
LOG_DIR="${OUTPUTS_DIR}/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/container-init-${TIMESTAMP}.log"

###############################################################################
# Credential tier tracking — set during setup, read by downstream stages
###############################################################################
# CRED_TIER values: tier1 | tier2 | tier3 | tier4
# CRED_IDENTITY:    STS caller identity ARN (empty if unknown)
# CRED_EXPIRY_UTC:  ISO-8601 expiry timestamp (empty if static or unknown)
# CRED_REMAINING_S: Seconds remaining until expiry (-1 if static/unknown)
CRED_TIER="tier4"
CRED_IDENTITY=""
CRED_EXPIRY_UTC=""
CRED_REMAINING_S="-1"
CRED_REPORT_FILE="${OUTPUTS_DIR}/credential-report.txt"

###############################################################################
# validate_credentials — Tiered credential security check
#
# Tries the most secure credential type first, then falls back:
#   Tier 1 (BEST):   MFA assumed-role — temporary, scoped, time-limited
#   Tier 2 (OK):     Static IAM user — long-lived, no role boundary
#   Tier 3 (EXPIRED): Credentials present but invalid/expired
#   Tier 4 (NONE):   No credentials file at all
#
# Sets global: CRED_TIER, CRED_IDENTITY, CRED_EXPIRY_UTC, CRED_REMAINING_S
###############################################################################
validate_credentials() {
  local creds_file="/home/vscode/.aws/credentials"
  local meta_file="/home/vscode/.aws/.session-meta"
  local profile="${AWS_PROFILE:-csoc}"

  echo "  ── Credential Security Check (most secure first) ──"
  echo ""

  # ── Tier 4: No credentials file at all ────────────────────────────────
  if [[ ! -f "$creds_file" ]]; then
    CRED_TIER="tier4"
    echo "  ✗ TIER 4 — NO CREDENTIALS"
    echo "    ~/.aws/credentials not found."
    echo ""
    if [[ ! -f "${REPO_DIR}/outputs/aws-config-snippet.ini" ]]; then
      echo "    FIRST-TIME SETUP REQUIRED:"
      echo "      1. Run: cd terraform/env/developer-identity && terraform apply"
      echo "      2. Register MFA device (see outputs/mfa-setup-instructions.txt)"
      echo ""
    fi
    echo "    Option A (recommended):  bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)"
    echo "    Option B (less secure):  bash scripts/mfa-session.sh --no-mfa    (on HOST)"
    echo ""
    echo "    Downstream stages (init/apply) will be BLOCKED."
    _write_credential_report
    return 1
  fi

  echo "  ✓ Credentials file found: ${creds_file}"

  # ── Read session metadata if available (written by mfa-session.sh) ────
  local meta_type="" meta_expiry="" meta_duration=""
  if [[ -f "$meta_file" ]]; then
    meta_type="$(grep '^CREDENTIAL_TYPE=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    meta_expiry="$(grep '^EXPIRY=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    meta_duration="$(grep '^DURATION_SECONDS=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    echo "  ✓ Session metadata found (type: ${meta_type:-unknown})"
  else
    echo "  ⚠ No session metadata (.session-meta) — will detect credential type via STS"
  fi

  # ── Check for session token in credentials file (fast pre-check) ──────
  local has_session_token=false
  if grep -A10 "^\[${profile}\]" "$creds_file" 2>/dev/null | grep -q "aws_session_token"; then
    has_session_token=true
  fi

  # ── Validate credentials via STS ──────────────────────────────────────
  echo "  Validating credentials (profile: ${profile})..."
  if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    CRED_TIER="tier3"
    echo ""
    echo "  ✗ TIER 3 — CREDENTIALS INVALID OR EXPIRED"
    if [[ "$has_session_token" == true ]]; then
      echo "    Session token present but STS validation failed."
      echo "    Likely cause: temporary credentials have expired."
    else
      echo "    Static credentials present but STS validation failed."
      echo "    Likely cause: access keys are invalid or deactivated."
    fi
    echo ""
    echo "    Renew on HOST:"
    echo "      Option A (recommended):  bash scripts/mfa-session.sh <MFA_CODE>"
    echo "      Option B (less secure):  bash scripts/mfa-session.sh --no-mfa"
    echo ""
    echo "    Downstream stages (init/apply) will be BLOCKED."
    _write_credential_report
    return 1
  fi

  CRED_IDENTITY="$(aws sts get-caller-identity --profile "$profile" --output text --query 'Arn' 2>/dev/null || echo 'unknown')"
  echo "  ✓ STS validation passed: ${CRED_IDENTITY}"

  # ── Tier 1: MFA assumed-role (temporary, scoped) ──────────────────────
  # Detection: session token present + STS identity contains "assumed-role"
  # OR session metadata says "assumed-role"
  if { [[ "$has_session_token" == true ]] && echo "$CRED_IDENTITY" | grep -q "assumed-role"; } \
     || [[ "$meta_type" == "assumed-role" ]]; then
    CRED_TIER="tier1"
    echo ""
    echo "  ✓ TIER 1 — MFA ASSUMED-ROLE (most secure)"
    echo "    Temporary credentials via role assumption with MFA."

    # ── Expiry check ────────────────────────────────────────────────────
    _check_expiry "$meta_expiry" "$meta_duration"

    if [[ "$CRED_REMAINING_S" -gt 0 && "$CRED_REMAINING_S" -lt 3600 ]]; then
      echo ""
      echo "  ⚠ WARNING: Credentials expire in less than 1 hour!"
      echo "    Remaining: $(( CRED_REMAINING_S / 60 )) minutes"
      echo "    Renew on HOST: bash scripts/mfa-session.sh <MFA_CODE>"
    elif [[ "$CRED_REMAINING_S" -gt 0 ]]; then
      echo "    Remaining: $(( CRED_REMAINING_S / 3600 ))h $(( (CRED_REMAINING_S % 3600) / 60 ))m"
    fi

    _write_credential_report
    return 0
  fi

  # ── Tier 2: Static IAM user credentials (long-lived) ─────────────────
  # Detection: no session token, STS identity shows user/... (not assumed-role)
  if [[ "$has_session_token" == false ]] || [[ "$meta_type" == "static" ]]; then
    CRED_TIER="tier2"
    echo ""
    echo "  ⚠ TIER 2 — STATIC IAM USER CREDENTIALS (less secure)"
    echo "    Long-lived access keys with no role boundary or time limit."
    echo "    These credentials do not expire but provide broader access"
    echo "    than necessary and lack audit trail of role assumption."
    echo ""
    echo "    RECOMMENDATION: Upgrade to Tier 1 (MFA assumed-role) for:"
    echo "      • Time-limited credentials (auto-expire after 12h)"
    echo "      • Scoped to the devcontainer IAM role"
    echo "      • MFA-gated access (proof of identity)"
    echo "    Run on HOST: bash scripts/mfa-session.sh <MFA_CODE>"

    _write_credential_report
    return 0
  fi

  # ── Fallback: assumed-role without session token (unusual) ────────────
  # This handles edge cases like instance profiles or SSO
  if echo "$CRED_IDENTITY" | grep -q "assumed-role"; then
    CRED_TIER="tier1"
    echo ""
    echo "  ✓ TIER 1 — ASSUMED-ROLE (detected via STS, no session metadata)"
    _write_credential_report
    return 0
  fi

  # Shouldn't reach here, but handle gracefully
  CRED_TIER="tier2"
  echo ""
  echo "  ⚠ TIER 2 — UNCLASSIFIED CREDENTIALS"
  echo "    Could not determine credential type. Treating as static/long-lived."
  _write_credential_report
  return 0
}

###############################################################################
# _check_expiry — Calculate remaining credential lifetime
#
# Sets: CRED_EXPIRY_UTC, CRED_REMAINING_S
###############################################################################
_check_expiry() {
  local meta_expiry="$1" meta_duration="$2"

  # Try metadata first
  if [[ -n "$meta_expiry" && "$meta_expiry" != "(static credentials"* ]]; then
    CRED_EXPIRY_UTC="$meta_expiry"
    local expiry_epoch now_epoch
    expiry_epoch="$(date -d "$meta_expiry" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if [[ "$expiry_epoch" -gt 0 ]]; then
      CRED_REMAINING_S=$(( expiry_epoch - now_epoch ))
      echo "    Expiry: ${CRED_EXPIRY_UTC}"
      return 0
    fi
  fi

  # Fallback: if we have a session-meta created_at + duration, compute expiry
  local meta_file="/home/vscode/.aws/.session-meta"
  if [[ -f "$meta_file" && -n "$meta_duration" ]]; then
    local created_at
    created_at="$(grep '^CREATED_AT=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    if [[ -n "$created_at" ]]; then
      local created_epoch now_epoch
      created_epoch="$(date -d "$created_at" +%s 2>/dev/null || echo 0)"
      now_epoch="$(date +%s)"
      if [[ "$created_epoch" -gt 0 ]]; then
        local expiry_epoch=$(( created_epoch + meta_duration ))
        CRED_REMAINING_S=$(( expiry_epoch - now_epoch ))
        CRED_EXPIRY_UTC="$(date -u -d "@${expiry_epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
        echo "    Expiry: ${CRED_EXPIRY_UTC} (computed from session metadata)"
        return 0
      fi
    fi
  fi

  echo "    Expiry: unknown (session metadata unavailable or unparseable)"
  CRED_REMAINING_S="-1"
}

###############################################################################
# _write_credential_report — Persist credential status to outputs/
###############################################################################
_write_credential_report() {
  local report_file="${CRED_REPORT_FILE}"
  local tier_label=""
  case "$CRED_TIER" in
    tier1) tier_label="TIER 1 — MFA Assumed-Role (most secure)" ;;
    tier2) tier_label="TIER 2 — Static IAM User (less secure)" ;;
    tier3) tier_label="TIER 3 — Invalid or Expired" ;;
    tier4) tier_label="TIER 4 — No Credentials" ;;
    *)     tier_label="UNKNOWN" ;;
  esac

  cat > "$report_file" <<REPORT
###############################################################################
# Credential Security Report
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
###############################################################################

TIER:           ${CRED_TIER}
STATUS:         ${tier_label}
IDENTITY:       ${CRED_IDENTITY:-none}
EXPIRY:         ${CRED_EXPIRY_UTC:-N/A}
REMAINING_SEC:  ${CRED_REMAINING_S}

TIER DEFINITIONS:
  Tier 1 (BEST):    MFA assumed-role — temporary, scoped, time-limited, MFA-gated
  Tier 2 (OK):      Static IAM user — long-lived access keys, no role boundary
  Tier 3 (EXPIRED): Credentials present but invalid or expired
  Tier 4 (NONE):    No credentials file found

UPGRADE INSTRUCTIONS:
  From Tier 2/3/4 to Tier 1:
    Run on HOST: bash scripts/mfa-session.sh <MFA_CODE>
  From Tier 4 (first time):
    1. cd terraform/env/developer-identity && terraform apply
    2. Register MFA device (see outputs/mfa-setup-instructions.txt)
    3. bash scripts/mfa-session.sh <MFA_CODE>

###############################################################################
REPORT

  echo "  → Report written to: ${report_file}"
}

###############################################################################
# _credential_warning — Print credential status banner (pre/post stage)
#
# Usage: _credential_warning "before" "apply"
#        _credential_warning "after"  "apply"
###############################################################################
_credential_warning() {
  local timing="$1" stage="$2"

  case "$CRED_TIER" in
    tier1)
      if [[ "$CRED_REMAINING_S" -gt 0 && "$CRED_REMAINING_S" -lt 3600 ]]; then
        echo ""
        echo "  ┌──────────────────────────────────────────────────────────────┐"
        echo "  │  ⚠ CREDENTIAL EXPIRY WARNING ($timing $stage)               │"
        echo "  │  Remaining: $(printf '%3d' $(( CRED_REMAINING_S / 60 ))) minutes                                      │"
        echo "  │  Credentials may expire during this operation.              │"
        echo "  │  Renew on HOST: bash scripts/mfa-session.sh <MFA_CODE>     │"
        echo "  └──────────────────────────────────────────────────────────────┘"
        echo ""
      fi
      ;;
    tier2)
      if [[ "$timing" == "after" ]]; then
        echo ""
        echo "  ┌──────────────────────────────────────────────────────────────┐"
        echo "  │  ⚠ SECURITY NOTICE (end of $stage)                          │"
        echo "  │  You are using STATIC IAM USER credentials (Tier 2).        │"
        echo "  │  These are long-lived and provide broader access than needed.│"
        echo "  │  Upgrade to Tier 1 for better security:                     │"
        echo "  │    bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)        │"
        echo "  └──────────────────────────────────────────────────────────────┘"
        echo ""
      fi
      ;;
  esac
}

###############################################################################
# _require_valid_credentials — Gate for stages that need working AWS creds
#
# Blocks on Tier 3 (expired) and Tier 4 (none). Returns 0 if creds are usable.
###############################################################################
_require_valid_credentials() {
  local stage="$1"
  if [[ "$CRED_TIER" == "tier3" || "$CRED_TIER" == "tier4" ]]; then
    echo ""
    echo "  ┌──────────────────────────────────────────────────────────────┐"
    echo "  │  ✗ STAGE BLOCKED: ${stage}                                   │"
    echo "  │  Credential tier: ${CRED_TIER} — credentials are unusable.   │"
    echo "  │  Fix on HOST:                                               │"
    echo "  │    bash scripts/mfa-session.sh <MFA_CODE>     (Tier 1, MFA) │"
    echo "  │    bash scripts/mfa-session.sh --no-mfa       (Tier 2)      │"
    echo "  └──────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Skipping ${stage} stage."
    return 1
  fi
  return 0
}

###############################################################################
# Parse flags into an associative array for O(1) lookups
###############################################################################
declare -A STAGES=()
for arg in "$@"; do
  STAGES["$arg"]=1
done

if [[ ${#STAGES[@]} -eq 0 ]]; then
  echo "=== Dev Container Init ==="
  echo "  No stages requested. Usage: bash container-init.sh [setup] [init] [apply]"
  echo "  Nothing to do."
  exit 0
fi

main() {
# ── Diagnostic trap: show exactly which command failed and where ──────────────
trap 'echo "" >&2; echo "  ✗ [container-init] Command failed at line $LINENO" >&2; echo "    Failed: $BASH_COMMAND" >&2' ERR

echo "=== Dev Container Init ==="
echo "  REPO_DIR:  $REPO_DIR"
echo "  ENV_DIR:   $ENV_DIR"
echo "  Log:       $LOG_FILE"
echo "  Stages:    $*"
echo ""

###############################################################################
# STAGE: setup — Environment, dirs, script copies, AWS creds, MCP, codex
###############################################################################
if [[ -n "${STAGES[setup]:-}" ]]; then
  echo ">>> [setup] Starting environment setup..."

  # ── 0. Clean generated files from previous runs ────────────────────────
  echo "  Cleaning generated files from previous runs..."
  rm -rf "${ENV_DIR}/.terraform" "${ENV_DIR}/.terraform.lock.hcl" 2>/dev/null || true
  rm -f  "${ENV_DIR}/install.sh" "${ENV_DIR}/destroy.sh" 2>/dev/null || true
  rm -f  "${OUTPUTS_DIR}/connect-csoc.sh" 2>/dev/null || true

  # ── 1. Required directories ───────────────────────────────────────────────
  # ~/.kube is NOT mounted — created empty; connect-csoc.sh populates it later
  mkdir -p /home/vscode/.kube /home/vscode/.aws 2>/dev/null || true
  mkdir -p "${OUTPUTS_DIR}/logs" "${OUTPUTS_DIR}/argo" "${OUTPUTS_DIR}/ssm-repo-secrets" 2>/dev/null || true
  mkdir -p "${REPO_DIR}/config/ssm-repo-secrets" 2>/dev/null || true

  # Workdir ownership: on Windows bind-mounts, chown can fail; don't break setup
  sudo chown -R vscode:vscode /workspaces 2>/dev/null || true

  # ── 2. Git safe directory ─────────────────────────────────────────────────
  git config --global --add safe.directory "${REPO_DIR}" || true

  # ── 3. Validate AWS credentials — Tiered security check ───────────────────
  # Tries most secure credential type first (Tier 1: MFA assumed-role),
  # then falls back through less secure options.
  # See validate_credentials() for full tier definitions.
  #
  # Credential mount path:
  #   mfa-session.sh writes to ~/.aws/eks-devcontainer/ on the HOST.
  #   devcontainer.json bind-mounts that dir → /home/vscode/.aws/
  #   so only scoped credentials (not all of ~/.aws) are visible.
  CSOC_PROFILE="${AWS_PROFILE:-csoc}"
  validate_credentials || true   # sets CRED_TIER, CRED_IDENTITY, etc.

  # ── 4. Resolve region for env file ────────────────────────────────────────
  # Read region from shared.auto.tfvars.json if present; otherwise fall back to
  # AWS_DEFAULT_REGION env var or 'us-east-1'.
  CONFIG_FILE="${REPO_DIR}/config/shared.auto.tfvars.json"
  CSOC_REGION=""
  if [[ -f "$CONFIG_FILE" ]] && command -v jq &>/dev/null; then
    CSOC_REGION="$(jq -r '.region // empty' "$CONFIG_FILE" 2>/dev/null || true)"
  fi
  CSOC_REGION="${CSOC_REGION:-${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}}"

  # ── 5. Write ~/.container-env with correct env vars ───────────────────────
  # TF_DATA_DIR redirects .terraform/ and .terraform.lock.hcl to a container-
  # local ext4 path so that git-clone chmod and lock-file rename succeed even
  # when the workspace is on a Windows bind-mount (DrvFs/NTFS).
  TF_DATA_DIR="/home/vscode/.terraform-data"
  mkdir -p "${TF_DATA_DIR}"

  ENV_FILE="/home/vscode/.container-env"
  cat > "$ENV_FILE" <<EOF
# Auto-generated by dev container init — $(date)
export REPO_ROOT="${REPO_DIR}"
export AWS_PROFILE="${CSOC_PROFILE}"
export AWS_REGION="${CSOC_REGION}"
export AWS_DEFAULT_REGION="${CSOC_REGION}"
export TF_DATA_DIR="${TF_DATA_DIR}"
EOF

  echo "  Wrote ${ENV_FILE}"

  # ── 6. Source in .bashrc so all new terminals pick it up ──────────────────
  BASHRC="/home/vscode/.bashrc"
  MARKER="# container-env-init"
  if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    {
      echo ""
      echo "$MARKER"
      echo '[ -f /home/vscode/.container-env ] && source /home/vscode/.container-env'
    } >> "$BASHRC"
  fi

  # Source it now for this session
  # shellcheck disable=SC1090
  source "$ENV_FILE"

  # ── 7. Copy deploy scripts to ENV_DIR for convenience ─────────────────────
  # Allows: cd terraform/env/aws/csoc-cluster && bash install.sh
  if [[ -d "$ENV_DIR" ]]; then
    echo "  Copying install.sh and destroy.sh to ${ENV_DIR}/"
    cp -f "${REPO_DIR}/scripts/install.sh" "${ENV_DIR}/install.sh" 2>/dev/null \
      || echo "  WARNING: Could not copy install.sh to ${ENV_DIR}/ (non-fatal)"
    cp -f "${REPO_DIR}/scripts/destroy.sh" "${ENV_DIR}/destroy.sh" 2>/dev/null \
      || echo "  WARNING: Could not copy destroy.sh to ${ENV_DIR}/ (non-fatal)"
    # chmod may fail on Windows bind-mounts — non-fatal
    chmod +x "${ENV_DIR}/install.sh" "${ENV_DIR}/destroy.sh" 2>/dev/null || true
  else
    echo "  WARNING: Env directory not found: ${ENV_DIR}"
    echo "  Skipping script copy."
  fi

  # ── 8. MCP config ───────────────────────────────────────────────────────────
  # Copy from .mcp/ source-of-truth to .vscode/mcp.json for VS Code pickup.
  # Write failures on Windows bind-mounts are non-fatal.
  if [[ -f "${REPO_DIR}/.mcp/mcp.json" ]]; then
    mkdir -p "${REPO_DIR}/.vscode" 2>/dev/null || true
    cp -f "${REPO_DIR}/.mcp/mcp.json" "${REPO_DIR}/.vscode/mcp.json" 2>/dev/null \
      && echo "  Copied .mcp/mcp.json → .vscode/mcp.json" \
      || echo "  WARNING: Could not copy .mcp/mcp.json (non-fatal)"
  elif [[ ! -f "${REPO_DIR}/.vscode/mcp.json" ]]; then
    mkdir -p "${REPO_DIR}/.vscode" 2>/dev/null || true
    cat > "${REPO_DIR}/.vscode/mcp.json" <<'JSON' 2>/dev/null || true
{
  "servers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "awslabs.aws-api-mcp-server": {
      "type": "stdio",
      "command": "uvx",
      "args": ["awslabs.aws-api-mcp-server@latest"],
      "env": {
        "AWS_REGION": "us-east-1"
      }
    }
  },
  "inputs": []
}
JSON
    [[ -f "${REPO_DIR}/.vscode/mcp.json" ]] \
      && echo "  Created fallback .vscode/mcp.json" \
      || echo "  WARNING: Could not create .vscode/mcp.json (non-fatal)"
  fi

  # ── 9. Codex sandbox config (restricted container workaround) ────────────
  mkdir -p /home/vscode/.codex 2>/dev/null || true
  CODEX_CONFIG="/home/vscode/.codex/config.toml"
  touch "${CODEX_CONFIG}" 2>/dev/null || true
  grep -Eq "^[[:space:]]*sandbox_mode[[:space:]]*=" "${CODEX_CONFIG}" 2>/dev/null || echo 'sandbox_mode = "danger-full-access"' >> "${CODEX_CONFIG}" 2>/dev/null || true
  grep -Eq "^[[:space:]]*approval_policy[[:space:]]*=" "${CODEX_CONFIG}" 2>/dev/null || echo 'approval_policy = "never"' >> "${CODEX_CONFIG}" 2>/dev/null || true
  grep -Eq "^[[:space:]]*features\.use_linux_sandbox_bwrap[[:space:]]*=" "${CODEX_CONFIG}" 2>/dev/null || echo "features.use_linux_sandbox_bwrap = false" >> "${CODEX_CONFIG}" 2>/dev/null || true

  if command -v unshare >/dev/null 2>&1 && ! unshare -Ur true >/dev/null 2>&1; then
    echo "  Unprivileged user namespaces blocked; Codex set to non-sandbox mode."
  fi

  echo ">>> [setup] Complete."
  echo ""
fi

###############################################################################
# STAGE: init — Push SSM secrets + terraform init
###############################################################################
if [[ -n "${STAGES[init]:-}" ]]; then
  echo ">>> [init] Starting init stage..."

  # Ensure env is loaded (in case setup was skipped but ran previously)
  [[ -f /home/vscode/.container-env ]] && source /home/vscode/.container-env

  # ── Credential gate: block on Tier 3/4 ──────────────────────────────────────
  if ! _require_valid_credentials "init"; then
    # Fall through — skip init but don't abort the script
    echo ">>> [init] SKIPPED (invalid credentials)."
    echo ""
  else
  _credential_warning "before" "init"

  # ── Push SSM repo secrets before init ─────────────────────────────────────
  # Runs before terraform init so that SSM secrets exist when Terraform
  # validates data sources. Gracefully skips if scripts don't exist.
  GENERATE_SCRIPT="${REPO_DIR}/scripts/ssm-repo-secrets/generate-ssm-payload.sh"
  PUSH_SCRIPT="${REPO_DIR}/scripts/ssm-repo-secrets/push-ssm-secrets.sh"

  if [[ -x "$GENERATE_SCRIPT" || -f "$GENERATE_SCRIPT" ]]; then
    echo ">>> [init] Generating SSM repo secret payloads..."
    bash "$GENERATE_SCRIPT" || echo "  WARNING: SSM payload generation failed (non-fatal)"

    if [[ -x "$PUSH_SCRIPT" || -f "$PUSH_SCRIPT" ]]; then
      echo ">>> [init] Pushing SSM repo secrets to AWS Secrets Manager..."
      bash "$PUSH_SCRIPT" || echo "  WARNING: SSM secret push failed (non-fatal)"
    fi
  else
    echo ">>> [init] No generate-ssm-payload.sh found — skipping SSM secrets push."
  fi

  # ── Run terraform init via install.sh ─────────────────────────────────────
  echo ">>> [init] Running install.sh init..."
  _init_rc=0
  bash "${REPO_DIR}/scripts/install.sh" init || _init_rc=$?
  if [[ $_init_rc -ne 0 ]]; then
    echo ""
    echo "  ✗ [init] install.sh init exited with code ${_init_rc}"
    echo "    Common causes: missing backend config, expired credentials,"
    echo "    or unconfigured config/shared.auto.tfvars.json."
    echo "    Check: ${LOG_FILE}"
    echo ""
  fi

  _credential_warning "after" "init"
  echo ">>> [init] Complete (exit code: ${_init_rc})."
  echo ""
  fi  # end credential gate
fi

###############################################################################
# STAGE: apply — terraform apply + connect to cluster
###############################################################################
if [[ -n "${STAGES[apply]:-}" ]]; then
  echo ">>> [apply] Starting apply stage..."

  # Ensure env is loaded
  [[ -f /home/vscode/.container-env ]] && source /home/vscode/.container-env

  # ── Credential gate: block on Tier 3/4 ──────────────────────────────────────
  if ! _require_valid_credentials "apply"; then
    echo ">>> [apply] SKIPPED (invalid credentials)."
    echo ""
  else
  _credential_warning "before" "apply"

  # ── Run terraform apply via install.sh ────────────────────────────────────
  echo ">>> [apply] Running install.sh apply..."
  _apply_rc=0
  bash "${REPO_DIR}/scripts/install.sh" apply || _apply_rc=$?
  if [[ $_apply_rc -ne 0 ]]; then
    echo ""
    echo "  ✗ [apply] install.sh apply exited with code ${_apply_rc}"
    echo "    Re-run manually: bash scripts/install.sh apply"
    echo "    Check: ${LOG_FILE}"
    echo ""
  fi

  _credential_warning "after" "apply"
  echo ">>> [apply] Complete (exit code: ${_apply_rc})."
  echo ""
  fi  # end credential gate
fi
###############################################################################
# STAGE: connect — kubeconfig + ArgoCD port-forward (no TF dependency)
#
# Runs inline. Does NOT depend on Terraform-generated connect-csoc.sh.
# Safe to call on every container start — only acts when the cluster is
# reachable.
###############################################################################
if [[ -n "${STAGES[connect]:-}" ]]; then
  echo ">>> [connect] Starting connect stage..."

  # Ensure env is loaded
  [[ -f /home/vscode/.container-env ]] && source /home/vscode/.container-env

  # Credential gate: block on Tier 3/4
  if ! _require_valid_credentials "connect"; then
    echo ">>> [connect] SKIPPED (invalid credentials)."
    echo ""
  else
  _credential_warning "before" "connect"

  CONFIG_FILE="${REPO_DIR}/config/shared.auto.tfvars.json"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "  WARNING: config/shared.auto.tfvars.json not found — skipping connect."
  elif ! command -v jq &>/dev/null; then
    echo "  WARNING: jq not installed — skipping connect."
  else
    # Derive cluster_name from csoc_alias (new convention) or fall back to legacy cluster_name
    local CSOC_ALIAS
    CSOC_ALIAS="$(jq -r '.csoc_alias // empty' "$CONFIG_FILE")"
    if [[ -n "$CSOC_ALIAS" ]]; then
      CLUSTER_NAME="${CSOC_ALIAS}-csoc-cluster"
    else
      CLUSTER_NAME="$(jq -r '.cluster_name // empty' "$CONFIG_FILE")"
    fi
    CLUSTER_REGION="$(jq -r '.region // "us-east-1"' "$CONFIG_FILE")"
    CLUSTER_PROFILE="${AWS_PROFILE:-$(jq -r '.aws_profile // "csoc"' "$CONFIG_FILE")}"

    if [[ -z "$CLUSTER_NAME" ]]; then
      echo "  WARNING: csoc_alias not set in config — skipping connect."
    else
      echo "  Cluster: ${CLUSTER_NAME}  Region: ${CLUSTER_REGION}  Profile: ${CLUSTER_PROFILE}"

      # ── Update kubeconfig ─────────────────────────────────────────────
      echo "  Updating kubeconfig..."
      if aws eks update-kubeconfig \
            --name "$CLUSTER_NAME" \
            --region "$CLUSTER_REGION" \
            --alias "$CLUSTER_NAME" \
            ${CLUSTER_PROFILE:+--profile "$CLUSTER_PROFILE"} 2>/dev/null; then
        echo "  ✓ kubeconfig updated"
      else
        echo "  ✗ Could not update kubeconfig (cluster may not exist yet)"
      fi

      # ── Verify connectivity ───────────────────────────────────────────
      if kubectl cluster-info --context "$CLUSTER_NAME" > /dev/null 2>&1; then
        echo "  ✓ Connected to cluster $CLUSTER_NAME"

        # ── Retrieve ArgoCD admin password ───────────────────────────────
        ARGOCD_PASSWORD=""
        for i in 1 2 3; do
          ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" --context "$CLUSTER_NAME" 2>/dev/null | base64 -d 2>/dev/null || true)
          if [[ -n "$ARGOCD_PASSWORD" ]]; then
            break
          fi
          echo "  waiting for argocd-initial-admin-secret... (attempt $i/3)"
          sleep 5
        done

        if [[ -n "$ARGOCD_PASSWORD" ]]; then
          echo "  ✓ ArgoCD admin password retrieved"
          # Export to .container-env so all new terminals pick it up
          ENV_FILE="/home/vscode/.container-env"
          # Remove any previous ARGOCD_ADMIN_PASSWORD line, then append
          sed -i '/^export ARGOCD_ADMIN_PASSWORD=/d' "$ENV_FILE" 2>/dev/null || true
          echo "export ARGOCD_ADMIN_PASSWORD=\"${ARGOCD_PASSWORD}\"" >> "$ENV_FILE"
          # Export for this session immediately
          export ARGOCD_ADMIN_PASSWORD="$ARGOCD_PASSWORD"
        else
          echo "  ✗ ArgoCD password not yet available (ArgoCD may still be deploying)"
        fi

        # ── Start ArgoCD port-forward (background) ─────────────────────
        if command -v lsof &>/dev/null && lsof -ti:8080 >/dev/null 2>&1; then
          kill $(lsof -ti:8080) 2>/dev/null || true
          sleep 1
        fi

        PF_LOG="${OUTPUTS_DIR}/port-forward.log"
        nohup kubectl port-forward -n argocd svc/argocd-server 8080:443 \
          --context "$CLUSTER_NAME" > "$PF_LOG" 2>&1 &
        PF_PID=$!
        disown "$PF_PID"
        sleep 2

        if kill -0 "$PF_PID" 2>/dev/null; then
          echo "  ✓ ArgoCD UI available at: https://localhost:8080"
          echo "    Username: admin"
          [[ -n "${ARGOCD_ADMIN_PASSWORD:-}" ]] && echo "    Password: (available in \$ARGOCD_ADMIN_PASSWORD env var)"
        else
          echo "  ✗ Port-forward failed to start (see $PF_LOG)"
        fi
      else
        echo "  Cluster not reachable — skipping ArgoCD setup (deploy first with: bash scripts/install.sh apply)"
      fi
    fi
  fi

  _credential_warning "after" "connect"
  echo ">>> [connect] Complete."
  echo ""
  fi  # end credential gate
fi
###############################################################################
# Done — Final credential status summary
###############################################################################
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  CREDENTIAL STATUS SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
case "$CRED_TIER" in
  tier1)
    echo "  ✓ Tier 1 — MFA Assumed-Role (most secure)"
    echo "    Identity: ${CRED_IDENTITY}"
    if [[ "$CRED_REMAINING_S" -gt 0 && "$CRED_REMAINING_S" -lt 3600 ]]; then
      echo "  ⚠ WARNING: Credentials expire in $(( CRED_REMAINING_S / 60 )) minutes!"
      echo "    Renew: bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)"
    elif [[ "$CRED_REMAINING_S" -gt 0 ]]; then
      echo "    Expires in: $(( CRED_REMAINING_S / 3600 ))h $(( (CRED_REMAINING_S % 3600) / 60 ))m"
    fi
    ;;
  tier2)
    echo "  ⚠ Tier 2 — Static IAM User (less secure)"
    echo "    Identity: ${CRED_IDENTITY}"
    echo "    Long-lived credentials — no expiry, broader access than needed."
    echo "    Upgrade: bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)"
    ;;
  tier3)
    echo "  ✗ Tier 3 — Credentials Invalid or Expired"
    echo "    Renew: bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)"
    ;;
  tier4)
    echo "  ✗ Tier 4 — No Credentials Found"
    echo "    Setup: bash scripts/mfa-session.sh <MFA_CODE>  (on HOST)"
    ;;
esac
echo "  Report: ${CRED_REPORT_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "=== Dev Container Init — All requested stages complete! ==="
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
