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

# Get timezone from log-config.yaml
CONFIG_FILE="${REPO_ROOT}/log-config.yaml"
if [ -f "$CONFIG_FILE" ]; then
  LOG_TIMEZONE=$(grep "^timezone:" "$CONFIG_FILE" | sed -E 's/^timezone: *"?([^"# ]+)"?.*/\1/' || echo "UTC")
else
  LOG_TIMEZONE="UTC"
fi

# Setup logging with organized directory structure
SCRIPT_NAME="prod"
TIMESTAMP=$(TZ="$LOG_TIMEZONE" date +%Y%m%d-%H%M%S)

# Get logs directory from log-config.yaml
if [ -f "$CONFIG_FILE" ]; then
  LOGS_BASE=$(grep "^logs_dir:" "$CONFIG_FILE" | sed -E 's/^logs_dir: *"?([^"# ]+)"?.*/\1/' || echo "outputs/logs")
else
  LOGS_BASE="outputs/logs"
fi

LOG_DIR="${REPO_ROOT}/${LOGS_BASE}/${SCRIPT_NAME}-${TIMESTAMP}"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/terragrunt.log"

# Export outputs directory for terragrunt.stack.hcl to use
export TG_OUTPUTS_DIR="$LOG_DIR"

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
# Detect if plan or apply is anywhere in the arguments
HAS_APPLY=false
HAS_PLAN=false
for arg in "$@"; do
  if [[ "$arg" == "apply" ]]; then
    HAS_APPLY=true
  elif [[ "$arg" == "plan" ]]; then
    HAS_PLAN=true
  fi
done

# Change to stack directory
cd "${STACK_DIR}"

# Execute terragrunt with all arguments
echo "Running terragrunt $@..."
terragrunt "$@" 2>&1 | tee -a "$LOG_FILE"
TERRAGRUNT_EXIT_CODE=$?

# Post-execution actions based on command
if [[ "$HAS_APPLY" == true ]]; then
  # Automatically configure cluster access after successful apply
  if [[ $TERRAGRUNT_EXIT_CODE -eq 0 ]]; then
    echo ""
    echo "✓ Apply successful! Configuring cluster access..."
    if [[ -f "${REPO_ROOT}/scripts/connect-cluster.sh" ]]; then
      # Export LOG_FILE so connect-cluster.sh uses the same log
      export LOG_FILE
      STACK_DIR="${STACK_DIR}" "${REPO_ROOT}/scripts/connect-cluster.sh" 2>&1 | tee -a "$LOG_FILE"
    else
      echo "Warning: connect-cluster.sh not found, skipping cluster configuration"
    fi
  fi

  # Generate state reports after apply
  echo ""
  echo "Generating state reports..."
  "${REPO_ROOT}/scripts/reports.sh" "${LOG_DIR}"
elif [[ "$HAS_PLAN" == true ]]; then
  # Generate reports after plan
  echo ""
  echo "Generating state reports..."
  "${REPO_ROOT}/scripts/reports.sh" "${LOG_DIR}"
fi

exit $TERRAGRUNT_EXIT_CODE

echo ""
echo "Log directory: ${LOG_DIR}"
echo "Terragrunt log: ${LOG_FILE}"
