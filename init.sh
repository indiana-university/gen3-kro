#!/usr/bin/env bash
# bootstrap/terragrunt-wrapper.sh
# Wrapper for Terragrunt operations

set -euo pipefail
IFS=$'\n\t'

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Source logging library
source "${SCRIPT_DIR}/scripts/lib-logging.sh"

# Configuration
LIVE_DIR="${REPO_ROOT}/terraform/live"
LOG_DIR="${REPO_ROOT}/outputs/logs"

# Create log directory
mkdir -p "$LOG_DIR"

# Set log file
LOG_FILE="${LOG_DIR}/terragrunt-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

# Usage information
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
  -v, --verbose    Enable verbose logging
  --debug          Enable Terraform debug logging (TF_LOG=DEBUG)
  -h, --help       Show this help message

EXAMPLES:
  $(basename "$0") plan
  $(basename "$0") apply
  $(basename "$0") destroy

EOF
}

# Main execution
main() {
  local command="$1"
  shift || true

  cd "$LIVE_DIR" || {
    log_error "Failed to change to directory: $LIVE_DIR"
    exit 1
  }

  case "$command" in
    plan)
      log_info "Running Terragrunt plan..."
      terragrunt plan "$@" 2>&1 | tee -a "$LOG_FILE"
      ;;
    apply)
      log_info "Running Terragrunt init..."
      terragrunt init "$@" 2>&1 | tee -a "$LOG_FILE"
      log_info "Running Terragrunt apply..."
      terragrunt apply "$@" --auto-approve 2>&1 | tee -a "$LOG_FILE"
      ;;
    destroy)
      log_info "Running Terragrunt destroy..."
      terragrunt destroy "$@" --auto-approve 2>&1 | tee -a "$LOG_FILE"
      ;;
    validate)
      log_info "Validating Terragrunt configuration..."
      terragrunt validate "$@" 2>&1 | tee -a "$LOG_FILE"
      ;;
    init)
      log_info "Running Terragrunt init..."
      terragrunt init "$@" 2>&1 | tee -a "$LOG_FILE"
      ;;
    output)
      log_info "Getting Terragrunt outputs..."
      terragrunt output "$@" 2>&1 | tee -a "$LOG_FILE"
      ;;
    show)
      log_info "Showing Terragrunt state..."
      terragrunt show "$@" 2>&1 | tee -a "$LOG_FILE"
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

# Parse arguments
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

main "$@"
