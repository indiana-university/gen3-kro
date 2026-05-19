#!/usr/bin/env bash
###############################################################################
# IAM Setup Script — Terragrunt Stack (iam-setup)
#
# Runs the Terragrunt stack at terragrunt/live/aws/iam-setup/ which manages:
#   • developer-identity — virtual MFA device + devcontainer assume-role
#   • aws-spoke          — ACK workload IAM roles for all enabled spokes
#
# Configuration is read automatically from config/shared.auto.tfvars.json
# by terragrunt.stack.hcl — no -var-file flag is needed.
#
# Usage:
#   bash scripts/iam-setup.sh [plan|apply|destroy]
#
# Actions:
#   plan    — terragrunt stack run plan   (default: shows changes, no AWS writes)
#   apply   — terragrunt stack run apply  (creates/updates IAM resources)
#   destroy — terragrunt stack run destroy (DESTRUCTIVE — prompts for confirmation)
#
# Prerequisites:
#   1. config/shared.auto.tfvars.json exists and is valid JSON
#   2. terragrunt >= 0.99.0 is installed
#   3. AWS credentials are active for the CSOC profile
#      (run scripts/mfa-session.sh on the host if needed)
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACK_DIR="${REPO_ROOT}/terragrunt/live/aws/iam-setup"
CONFIG_FILE="${REPO_ROOT}/config/shared.auto.tfvars.json"
LOG_DIR="${REPO_ROOT}/outputs/logs"

mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# ── Logging helpers ──────────────────────────────────────────────────────────
log_info()    { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
log_success() { echo -e "\033[0;32m[OK]\033[0m    $*"; }
log_warn()    { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
log_error()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
log_stage()   { echo -e "\n\033[1;36m══ $* ══\033[0m"; }

die() { log_error "$*"; exit 1; }

###############################################################################
# Parse action
###############################################################################
ACTION="${1:-plan}"
case "${ACTION}" in
  plan|apply|destroy) ;;
  *)
    echo "Usage: bash scripts/iam-setup.sh [plan|apply|destroy]"
    echo "  plan    — show changes (default)"
    echo "  apply   — create/update IAM resources"
    echo "  destroy — remove IAM resources (prompts for confirmation)"
    exit 1
    ;;
esac

LOG_FILE="${LOG_DIR}/iam-setup-${ACTION}-${TIMESTAMP}.log"

###############################################################################
# Validate prerequisites
###############################################################################
validate_prerequisites() {
  log_stage "Validating prerequisites"

  if ! command -v jq &>/dev/null; then
    die "jq is not installed. Install: brew install jq  or  sudo apt install jq"
  fi

  if ! command -v terragrunt &>/dev/null; then
    die "terragrunt is not installed."
  fi

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    die "Config file not found: ${CONFIG_FILE}
  Copy config/shared.auto.tfvars.json.example → config/shared.auto.tfvars.json and fill in values."
  fi

  if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
    die "config/shared.auto.tfvars.json is not valid JSON."
  fi

  local profile
  profile="$(jq -r '.aws_profile // "csoc"' "${CONFIG_FILE}")"
  if ! aws sts get-caller-identity --profile "${profile}" &>/dev/null; then
    die "AWS credentials invalid for profile '${profile}'. Run scripts/mfa-session.sh on the host to refresh."
  fi
  log_success "AWS credentials valid (profile: ${profile})"

  if [[ ! -f "${STACK_DIR}/terragrunt.stack.hcl" ]]; then
    die "Stack not found: ${STACK_DIR}/terragrunt.stack.hcl"
  fi

  log_success "All prerequisites OK"
}

###############################################################################
# Print config summary from shared.auto.tfvars.json
###############################################################################
print_config_summary() {
  log_stage "Configuration (from config/shared.auto.tfvars.json)"

  local csoc_alias region backend_bucket spokes
  csoc_alias="$(jq -r '.csoc_alias // "csoc"' "${CONFIG_FILE}")"
  region="$(jq -r '.region // "us-east-1"' "${CONFIG_FILE}")"
  backend_bucket="$(jq -r '.backend_bucket // ""' "${CONFIG_FILE}")"
  spokes="$(jq -r '[.spokes[] | select(.enabled == true) | .alias] | join(", ")' "${CONFIG_FILE}" 2>/dev/null || echo "(none)")"

  log_info "  CSOC alias   : ${csoc_alias}"
  log_info "  Region       : ${region}"
  log_info "  State bucket : ${backend_bucket}"
  log_info "  Spokes       : ${spokes}"
  log_info "  Stack dir    : ${STACK_DIR}"
}

###############################################################################
# Destroy guard
###############################################################################
confirm_destroy() {
  log_warn "This will DESTROY IAM resources managed by the iam-setup stack."
  log_warn "Resources include: devcontainer role, virtual MFA device, and ACK spoke roles."
  echo ""
  read -r -p "Type 'yes' to confirm destroy: " answer
  if [[ "${answer}" != "yes" ]]; then
    log_info "Destroy cancelled."
    exit 0
  fi
}

###############################################################################
# Run terragrunt stack
###############################################################################
run_stack() {
  log_stage "Running: terragrunt stack run ${ACTION}"
  log_info "  Log: ${LOG_FILE}"

  cd "${STACK_DIR}"
  terragrunt stack run "${ACTION}" 2>&1 | tee "${LOG_FILE}"

  log_success "terragrunt stack run ${ACTION} complete"
}

###############################################################################
# Main
###############################################################################
validate_prerequisites
print_config_summary

if [[ "${ACTION}" == "destroy" ]]; then
  confirm_destroy
fi

run_stack
