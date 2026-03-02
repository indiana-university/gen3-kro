#!/usr/bin/env bash
###############################################################################
# Install Script — CSOC EKS Stack (Plain Terraform)
#
# Single entry point for Terraform operations against the unified root module
# at terraform/env/aws/csoc-cluster/.
#
# Prerequisites:
#   config/shared.auto.tfvars.json — single source of truth (copy from .example)
#
# Usage:
#   bash install.sh              # Defaults to 'apply' + connect to cluster
#   bash install.sh init         # terraform init only
#   bash install.sh plan         # terraform plan (no changes)
#   bash install.sh apply        # terraform apply + connect (default)
#
# All output is logged to outputs/logs/install-<action>-<timestamp>.log
###############################################################################
set -euo pipefail

###############################################################################
# Paths
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
ENV_DIR="${REPO_ROOT}/terraform/env/aws/csoc-cluster"
OUTPUTS_DIR="${REPO_ROOT}/outputs"
LOG_DIR="${OUTPUTS_DIR}/logs"
CONFIG_DIR="${REPO_ROOT}/config"
CONFIG_FILE="${CONFIG_DIR}/shared.auto.tfvars.json"

mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

###############################################################################
# Parse action
###############################################################################
ACTION="${1:-apply}"
case "$ACTION" in
  init|plan|apply) ;;
  *)
    echo "Usage: bash install.sh [init|plan|apply]"
    echo "  init   — terraform init"
    echo "  plan   — terraform plan (no changes)"
    echo "  apply  — terraform apply + connect (default)"
    exit 1
    ;;
esac

LOG_FILE="${LOG_DIR}/install-${ACTION}-${TIMESTAMP}.log"

###############################################################################
# Helpers
###############################################################################
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() {
  log "FATAL: $*"
  exit 1
}

# When TF_DATA_DIR is set (container environment), terraform writes modules and
# providers to that ext4 path but still creates .terraform.lock.hcl (and its
# temp file) in the current working directory.  On a Windows DrvFs bind-mount
# the chmod on the temp file fails.  Work around this by running terraform from
# a container-local directory that symlinks back to the real .tf files.
#
# Also symlinks shared.auto.tfvars.json into the workdir so Terraform
# auto-loads it — no -var-file flag needed.
setup_workdir() {
  if [[ -z "${TF_DATA_DIR:-}" ]]; then
    # Running outside the devcontainer — use ENV_DIR directly
    WORK_DIR="$ENV_DIR"
  else
    WORK_DIR="/home/vscode/.terraform-workdir/terraform/env/aws/csoc-cluster"
    mkdir -p "$WORK_DIR"
    # Symlink every .tf file from the real env dir
    for f in "${ENV_DIR}"/*.tf; do
      [[ -f "$f" ]] && ln -sfn "$f" "$WORK_DIR/$(basename "$f")"
    done
    # Symlink catalog so ../../../catalog/modules/csoc-cluster resolves
    ln -sfn "${REPO_ROOT}/terraform/catalog" "/home/vscode/.terraform-workdir/terraform/catalog"
    log "  WORK_DIR: $WORK_DIR  (container-local, TF_DATA_DIR=${TF_DATA_DIR})"
  fi

  # Symlink shared.auto.tfvars.json into the working directory so Terraform
  # auto-loads it without an explicit -var-file argument.
  ln -sfn "$CONFIG_FILE" "$WORK_DIR/shared.auto.tfvars.json"
}

###############################################################################
# Step 0: Validate prerequisites
###############################################################################
validate_prerequisites() {
  log ">>> [Prereq] Validating prerequisites..."

  # terraform
  if ! command -v terraform &>/dev/null; then
    die "terraform is not installed."
  fi

  # jq (needed to read backend config from the JSON)
  if ! command -v jq &>/dev/null; then
    die "jq is not installed."
  fi

  # shared config file
  if [[ ! -f "$CONFIG_FILE" ]]; then
    die "shared.auto.tfvars.json not found at ${CONFIG_FILE}." \
      $'\n'"  Copy config/shared.auto.tfvars.json.example → config/shared.auto.tfvars.json and fill in values."
  fi

  # Validate the JSON is well-formed
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    die "shared.auto.tfvars.json is not valid JSON."
  fi

  # AWS credentials — use AWS_PROFILE (set by devcontainer) or fall back to 'csoc'
  # KNOWN LIMITATION: sts:GetCallerIdentity succeeds even with expired MFA sessions
  # if the underlying IAM user credentials are still valid. This can give a false
  # positive — terraform plan/apply may still fail on actual API calls.
  # See docs/platform-status.md R2 for details and future improvement plan.
  local profile="${AWS_PROFILE:-csoc}"
  if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    log "  AWS credentials valid (profile: ${profile})"
  else
    die "AWS credentials invalid for profile '${profile}'. Run mfa-session.sh on the host to refresh credentials."
  fi

  # Env dir exists
  if [[ ! -d "$ENV_DIR" ]]; then
    die "Terraform env directory not found: ${ENV_DIR}"
  fi

  log ">>> [Prereq] All prerequisites OK."
}

###############################################################################
# Step 1: terraform init
###############################################################################
terraform_init() {
  log ">>> [Step 1] Running terraform init..."

  setup_workdir
  cd "$WORK_DIR"

  # Extract backend config from the shared JSON
  local backend_bucket backend_key backend_region
  backend_bucket="$(jq -r '.backend_bucket // empty' "$CONFIG_FILE")"
  backend_key="$(jq -r '.backend_key // empty' "$CONFIG_FILE")"
  backend_region="$(jq -r '.backend_region // empty' "$CONFIG_FILE")"

  if [[ -z "$backend_bucket" || -z "$backend_key" || -z "$backend_region" ]]; then
    die "backend_bucket, backend_key, and backend_region must be set in ${CONFIG_FILE}"
  fi

  # TF_DATA_DIR (set by container-init.sh) redirects .terraform/ to a container-
  # local ext4 path. Check there first, then fall back to in-tree .terraform.
  local tf_dir="${TF_DATA_DIR:-${WORK_DIR}/.terraform}"

  # Only re-init if .terraform directory doesn't exist or 'init' action forces it.
  if [[ "$ACTION" == "init" || ! -d "$tf_dir" ]]; then
    log "  Backend: bucket=${backend_bucket} key=${backend_key} region=${backend_region}"
    log "  TF_DATA_DIR: ${TF_DATA_DIR:-<not set>}"
    terraform init \
      -reconfigure \
      -backend-config="bucket=${backend_bucket}" \
      -backend-config="key=${backend_key}" \
      -backend-config="region=${backend_region}"
  else
    log "  .terraform directory exists (${tf_dir}) — skipping init (use 'init' action to force)"
  fi

  log ">>> [Step 1] Init complete."
}

###############################################################################
# Step 2: terraform plan / apply
###############################################################################
terraform_action() {
  cd "$WORK_DIR"

  local start_time end_time rc=0
  start_time="$(date +%s)"

  case "$ACTION" in
    plan)
      log ">>> [Step 2] Running terraform plan..."
      terraform plan || rc=$?
      ;;
    apply)
      log ">>> [Step 2] Running terraform apply -auto-approve..."
      terraform apply -auto-approve || rc=$?
      ;;
  esac

  end_time="$(date +%s)"
  if [[ $rc -ne 0 ]]; then
    log ">>> Terraform ${ACTION} FAILED (exit ${rc}) after $(( end_time - start_time ))s"
    return $rc
  fi
  log ">>> Terraform ${ACTION} completed in $(( end_time - start_time ))s"
}

###############################################################################
# Step 3: Connect to cluster (apply only)
###############################################################################
connect_to_cluster() {
  if [[ "$ACTION" != "apply" ]]; then
    return 0
  fi

  log ">>> [Step 3] Looking for connect-csoc.sh..."

  local connect_script=""
  # Check multiple possible locations where argocd-bootstrap may write it
  for candidate in \
    "${OUTPUTS_DIR}/connect-csoc.sh" \
    "${ENV_DIR}/connect-csoc.sh" \
    "${REPO_ROOT}/connect-csoc.sh"; do
    if [[ -f "$candidate" ]]; then
      connect_script="$candidate"
      break
    fi
  done

  if [[ -n "$connect_script" ]]; then
    log "  Found: ${connect_script}"
    # chmod may fail on NTFS bind-mounts — non-fatal; we invoke with 'bash' anyway
    chmod +x "$connect_script" 2>/dev/null || true
    bash "$connect_script"
  else
    log "  WARNING: connect-csoc.sh not found."
    log "  The argocd-bootstrap module may not have generated it yet."
    log "  Checked: ${OUTPUTS_DIR}/, ${ENV_DIR}/"
  fi
}

###############################################################################
# Main
###############################################################################
main() {
  log "============================================="
  log " CSOC Stack Install — ${ACTION}"
  log " Env Dir:  ${ENV_DIR}"
  log " Config:   ${CONFIG_FILE}"
  log " Log:      ${LOG_FILE}"
  log " Started:  $(date)"
  log "============================================="

  validate_prerequisites

  # Export runtime-computed paths as TF_VAR_ so Terraform can use them
  # without needing them in shared.auto.tfvars.json (they vary per-machine).
  export TF_VAR_outputs_dir="${OUTPUTS_DIR}"
  export TF_VAR_stack_dir="${ENV_DIR}"

  terraform_init

  # For 'init' action, stop after init
  if [[ "$ACTION" == "init" ]]; then
    log ""
    log "============================================="
    log " Init complete — $(date)"
    log " Log saved to: ${LOG_FILE}"
    log "============================================="
    return 0
  fi

  terraform_action
  connect_to_cluster

  log ""
  log "============================================="
  log " ${ACTION^} complete — $(date)"
  log " Log saved to: ${LOG_FILE}"
  log "============================================="
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
