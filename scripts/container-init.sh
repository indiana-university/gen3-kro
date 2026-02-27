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
  mkdir -p /home/vscode/.kube /home/vscode/.aws
  mkdir -p "${OUTPUTS_DIR}/logs" "${OUTPUTS_DIR}/argo" "${OUTPUTS_DIR}/ssm-repo-secrets"
  mkdir -p "${REPO_DIR}/config/ssm-repo-secrets"

  # Workdir ownership: on Windows bind-mounts, chown can fail; don't break setup
  sudo chown -R vscode:vscode /workspaces 2>/dev/null || true

  # ── 2. Git safe directory ─────────────────────────────────────────────────
  git config --global --add safe.directory "${REPO_DIR}" || true

  # ── 3. Validate AWS credentials (~/.aws from host bind-mount) ─────────────────────
  # mfa-session.sh on the host writes credentials to ~/.aws/credentials.
  # devcontainer.json bind-mounts ~/.aws → /home/vscode/.aws so they're available here.
  # mfa-session.sh writes to ~/.aws/eks-devcontainer/credentials on the HOST.
  # devcontainer.json bind-mounts ~/.aws/eks-devcontainer/ → /home/vscode/.aws/
  # so only those scoped credentials (not all of ~/.aws) are visible in the container.
  CREDS_FILE="/home/vscode/.aws/credentials"
  if [[ -f "$CREDS_FILE" ]]; then
    echo "  AWS credentials file found: ${CREDS_FILE}"
  else
    echo "  WARNING: ~/.aws/credentials not found."
    if [[ ! -f "${REPO_DIR}/outputs/aws-config-snippet.ini" ]]; then
      echo "  FIRST-TIME SETUP REQUIRED:"
      echo "    1. Run: cd terraform/env/developer-identity && terraform apply"
      echo "    2. Register MFA device (see outputs/mfa-setup-instructions.txt)"
    fi
    echo "  Option A (MFA):     bash scripts/mfa-session.sh <CODE>    (on HOST)"
    echo "  Option B (no MFA):  bash scripts/mfa-session.sh --no-mfa  (on HOST)"
    echo "  Some operations will fail without valid credentials."
  fi

  # Validate the csoc profile works
  CSOC_PROFILE="${AWS_PROFILE:-csoc}"
  echo "  Validating AWS credentials (profile: ${CSOC_PROFILE})..."
  if aws sts get-caller-identity --profile "$CSOC_PROFILE" &>/dev/null; then
    CALLER_ID="$(aws sts get-caller-identity --profile "$CSOC_PROFILE" --output text --query 'Arn' 2>/dev/null || echo 'unknown')"
    echo "  AWS identity: ${CALLER_ID}"

    if echo "$CALLER_ID" | grep -q "assumed-role"; then
      echo "  Using temporary credentials (assumed-role) — good"
    else
      echo "  WARNING: Using static IAM user credentials."
      echo "    For better security, use assumed-role credentials."
    fi
  else
    echo "  WARNING: AWS credentials not valid for profile '${CSOC_PROFILE}'"
    echo "    Run on HOST: bash scripts/mfa-session.sh <CODE>     (option A: MFA)"
    echo "             or: bash scripts/mfa-session.sh --no-mfa   (option B: admin static)"
    echo "    Credentials must be in ~/.aws/eks-devcontainer/credentials before container starts."
    echo "    Terraform operations will fail until credentials are configured."
  fi

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
    cp -f "${REPO_DIR}/scripts/install.sh" "${ENV_DIR}/install.sh"
    cp -f "${REPO_DIR}/scripts/destroy.sh" "${ENV_DIR}/destroy.sh"
    # chmod may fail on Windows bind-mounts — non-fatal
    chmod +x "${ENV_DIR}/install.sh" "${ENV_DIR}/destroy.sh" 2>/dev/null || true
  else
    echo "  WARNING: Env directory not found: ${ENV_DIR}"
    echo "  Skipping script copy."
  fi

  # ── 8. MCP config ───────────────────────────────────────────────────────────
  # Copy from .mcp/ source-of-truth to .vscode/mcp.json for VS Code pickup.
  if [[ -f "${REPO_DIR}/.mcp/mcp.json" ]]; then
    mkdir -p "${REPO_DIR}/.vscode"
    cp -f "${REPO_DIR}/.mcp/mcp.json" "${REPO_DIR}/.vscode/mcp.json"
    echo "  Copied .mcp/mcp.json → .vscode/mcp.json"
  elif [[ ! -f "${REPO_DIR}/.vscode/mcp.json" ]]; then
    mkdir -p "${REPO_DIR}/.vscode"
    cat > "${REPO_DIR}/.vscode/mcp.json" <<'JSON'
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
    echo "  Created fallback .vscode/mcp.json"
  fi

  # ── 9. Codex sandbox config (restricted container workaround) ────────────
  mkdir -p /home/vscode/.codex
  CODEX_CONFIG="/home/vscode/.codex/config.toml"
  touch "${CODEX_CONFIG}"
  grep -Eq "^[[:space:]]*sandbox_mode[[:space:]]*=" "${CODEX_CONFIG}" || echo 'sandbox_mode = "danger-full-access"' >> "${CODEX_CONFIG}"
  grep -Eq "^[[:space:]]*approval_policy[[:space:]]*=" "${CODEX_CONFIG}" || echo 'approval_policy = "never"' >> "${CODEX_CONFIG}"
  grep -Eq "^[[:space:]]*features\.use_linux_sandbox_bwrap[[:space:]]*=" "${CODEX_CONFIG}" || echo "features.use_linux_sandbox_bwrap = false" >> "${CODEX_CONFIG}"

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
  bash "${REPO_DIR}/scripts/install.sh" init

  echo ">>> [init] Complete."
  echo ""
fi

###############################################################################
# STAGE: apply — terraform apply + connect to cluster
###############################################################################
if [[ -n "${STAGES[apply]:-}" ]]; then
  echo ">>> [apply] Starting apply stage..."

  # Ensure env is loaded
  [[ -f /home/vscode/.container-env ]] && source /home/vscode/.container-env

  # ── Guard: require CONTAINER_AUTO_APPLY=true for auto-approve ─────────────
  # Prevents accidental terraform apply when the script is run manually outside
  # a fresh devcontainer init. Set CONTAINER_AUTO_APPLY=true in .container-env
  # or devcontainer.json containerEnv to enable auto-apply.
  if [[ "${CONTAINER_AUTO_APPLY:-false}" != "true" ]]; then
    echo "  CONTAINER_AUTO_APPLY is not set to 'true' — skipping auto-approve apply."
    echo "  To enable: export CONTAINER_AUTO_APPLY=true (or set in devcontainer.json containerEnv)"
    echo "  To apply manually: bash scripts/install.sh apply"
    echo ">>> [apply] Skipped (guarded)."
    echo ""
  else
    # ── Run terraform apply via install.sh ──────────────────────────────────
    echo ">>> [apply] Running install.sh apply..."
    bash "${REPO_DIR}/scripts/install.sh" apply

    echo ">>> [apply] Complete."
    echo ""
  fi
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

  echo ">>> [connect] Complete."
  echo ""
fi
###############################################################################
# Done
###############################################################################
echo "=== Dev Container Init — All requested stages complete! ==="
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
