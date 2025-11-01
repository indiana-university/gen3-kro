#!/usr/bin/env bash
###############################################################################
# Terragrunt Wrapper Script - Production Version
# Uses branch from secrets.yaml as-is (no auto-update)
###############################################################################

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
STACK_DIR="${STACK_DIR:-${REPO_ROOT}/live/aws/us-east-1/gen3-kro-dev}"

# Verify stack directory exists
if [[ ! -f "${STACK_DIR}/terragrunt.stack.hcl" ]]; then
  echo "ERROR: Stack directory not found or missing terragrunt.stack.hcl: ${STACK_DIR}"
  echo "Set STACK_DIR environment variable to specify a different location"
  exit 1
fi

# Setup logging
LOG_DIR="${REPO_ROOT}/outputs/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/terragrunt-$(date +%Y%m%d-%H%M%S).log"

echo "Stack directory: ${STACK_DIR}"
echo "Log file: ${LOG_FILE}"
echo ""

###############################################################################
# Usage Information
###############################################################################
usage() {
  cat <<EOF
Usage: $(basename "$0") [COMMAND] [OPTIONS]

Production version - uses branch from secrets.yaml without modification.

Terragrunt wrapper that sets up logging and working directory.
Passes all commands and flags directly to Terragrunt.

COMMON COMMANDS:
  init        Initialize Terragrunt stack
  plan        Preview infrastructure changes
  apply       Deploy infrastructure
  destroy     Destroy infrastructure
  output      Show stack outputs
  validate    Validate configuration
  run-all     Run command across all modules
  
  Any other Terragrunt command is also supported

ENVIRONMENT VARIABLES:
  STACK_DIR   Path to stack directory (default: live/aws/us-east-1/gen3-kro-dev)

EXAMPLES:
  $(basename "$0") init
  $(basename "$0") plan
  $(basename "$0") apply
  $(basename "$0") run-all apply
  $(basename "$0") run-all plan
  $(basename "$0") state list
  STACK_DIR=/path/to/stack $(basename "$0") plan

EOF
}

###############################################################################
# Main Execution
###############################################################################
if [ $# -eq 0 ]; then
  usage
  exit 1
fi

# Handle help flags
if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
  usage
  exit 0
fi

# All arguments are passed to terragrunt
COMMAND="$1"

# Change to stack directory
cd "${STACK_DIR}"

# Execute terragrunt with all arguments, with special handling for apply
if [[ "$COMMAND" == "apply" ]] || [[ "$COMMAND" == "run-all" && "${2:-}" == "apply" ]]; then
  echo "Running terragrunt $@..."
  terragrunt "$@" 2>&1 | tee -a "$LOG_FILE"
  APPLY_EXIT_CODE=$?

  # Automatically configure cluster access after successful apply
  if [[ $APPLY_EXIT_CODE -eq 0 ]]; then
    echo ""
    echo "✓ Apply successful! Configuring cluster access..."
    if [[ -f "${REPO_ROOT}/scripts/connect-cluster.sh" ]]; then
      STACK_DIR="${STACK_DIR}" "${REPO_ROOT}/scripts/connect-cluster.sh"
    else
      echo "Warning: connect-cluster.sh not found, skipping cluster configuration"
    fi
  fi
  exit $APPLY_EXIT_CODE
else
  echo "Running terragrunt $@..."
  terragrunt "$@" 2>&1 | tee -a "$LOG_FILE"
fi

echo ""
echo "Log saved to: ${LOG_FILE}"
