#!/usr/bin/env bash
###############################################################################
# Terragrunt Wrapper Script
# Wrapper for Terragrunt operations with logging and dry-run support
###############################################################################

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Configuration and Setup
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/scripts"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

source "${SCRIPT_DIR}/lib-logging.sh"

LOG_DIR="${REPO_ROOT}/outputs/logs"

mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/terragrunt-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

###############################################################################
# Usage Information
###############################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND [OPTIONS]

COMMAND:
  plan        Generate execution plan
  apply       Apply changes
  destroy     Destroy infrastructure
  validate    Validate Terragrunt configuration
  init        Initialize Terragrunt
  output      Show outputs
  show        Show current state

OPTIONS:
  -n, --dry-run    Show what would be executed without running
  -v, --verbose    Enable verbose logging
  --debug          Enable Terraform debug logging (TF_LOG=DEBUG)
  -h, --help       Show this help message

EXAMPLES:
  $(basename "$0") plan
  $(basename "$0") apply
  $(basename "$0") --dry-run destroy

EOF
}

###############################################################################
# Argument Parsing
###############################################################################
DRY_RUN=0
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --debug)
      DEBUG=1
      export TF_LOG=DEBUG
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

###############################################################################
# Main Execution Function
###############################################################################
main() {
  local command="$1"
  shift || true

  case "$command" in
    plan)
      log_info "Running Terragrunt plan..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt plan $*"
      else
        terragrunt plan "$@" 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    apply)
      log_info "Applying Terragrunt stack..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt apply --all $*"
      else
        terragrunt apply --all "$@" 2>&1 | tee -a "$LOG_FILE"
        apply_exit_code=$?

        # Automatically configure cluster access after successful apply
        if [[ $apply_exit_code -eq 0 ]]; then
          log_info "Apply successful, configuring cluster access..."
          if [[ -f "${SCRIPT_DIR}/connect-cluster.sh" ]]; then
            "${SCRIPT_DIR}/connect-cluster.sh"
          else
            log_warn "connect-cluster.sh not found, skipping cluster configuration"
          fi
        fi
      fi
      ;;
    destroy)
      log_info "Running Terragrunt destroy..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt destroy $* --auto-approve"
      else
        terragrunt destroy "$@" --auto-approve 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    validate)
      log_info "Validating Terragrunt configuration..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt validate $*"
      else
        terragrunt validate "$@" 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    init)
      log_info "Running Terragrunt init..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt init $*"
      else
        terragrunt init "$@" 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    output)
      log_info "Getting Terragrunt outputs..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt output $*"
      else
        terragrunt output "$@" 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    show)
      log_info "Showing Terragrunt state..."
      if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY RUN: would run: terragrunt show $*"
      else
        terragrunt show "$@" 2>&1 | tee -a "$LOG_FILE"
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown command: $command"
      usage
      exit 1
      ;;
  esac
}

###############################################################################
# Script Entry Point
###############################################################################
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

main "$@"

###############################################################################
# End of File
###############################################################################
