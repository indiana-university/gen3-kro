#!/usr/bin/env bash
###############################################################################
# Terragrunt Wrapper Script
# Simple wrapper for Terragrunt stack operations
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

# Get current git branch
CURRENT_BRANCH=$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

# Update secrets.yaml with current branch if it exists
SECRETS_FILE="${STACK_DIR}/secrets.yaml"
if [[ -f "${SECRETS_FILE}" ]]; then
  echo "Updating secrets.yaml with current branch: ${CURRENT_BRANCH}"
  sed -i "s|branch: \".*\"|branch: \"${CURRENT_BRANCH}\"|g" "${SECRETS_FILE}"
  echo "✓ Updated all branch references in secrets.yaml to: ${CURRENT_BRANCH}"
else
  echo "Warning: secrets.yaml not found at ${SECRETS_FILE}"
  echo "Skipping branch update (this is normal if using secrets-example.yaml)"
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
Usage: $(basename "$0") COMMAND

COMMAND:
  plan        Preview infrastructure changes
  apply       Deploy infrastructure
  destroy     Destroy infrastructure
  output      Show stack outputs
  validate    Validate configuration

ENVIRONMENT VARIABLES:
  STACK_DIR   Path to stack directory (default: live/aws/us-east-1/gen3-kro-dev)

EXAMPLES:
  $(basename "$0") plan
  $(basename "$0") apply
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

COMMAND="$1"
shift || true

# Change to stack directory
cd "${STACK_DIR}"

# Execute command
case "$COMMAND" in
  plan)
    echo "Running terragrunt plan..."
    terragrunt plan -all "$@" 2>&1 | tee -a "$LOG_FILE"
    ;;
  apply)
    echo "Running terragrunt apply..."
    terragrunt apply -all "$@" 2>&1 | tee -a "$LOG_FILE"
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
    ;;
  destroy)
    echo "Running terragrunt destroy..."
    terragrunt destroy -all "$@" 2>&1 | tee -a "$LOG_FILE"
    ;;
  validate)
    echo "Running terragrunt validate..."
    terragrunt validate -all "$@" 2>&1 | tee -a "$LOG_FILE"
    ;;
  output)
    echo "Running terragrunt output..."
    terragrunt output "$@" 2>&1 | tee -a "$LOG_FILE"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac

echo ""
echo "Log saved to: ${LOG_FILE}"

