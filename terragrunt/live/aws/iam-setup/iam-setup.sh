#!/usr/bin/env bash
###############################################################################
# IAM Setup Script - Terragrunt Stack (iam-setup)
#
# Thin wrapper around `terragrunt stack run` for the iam-setup stack.
# The stack reads config/shared.auto.tfvars.json via terragrunt.stack.hcl.
#
# Usage:
#   bash terragrunt/live/aws/iam-setup/iam-setup.sh [plan|apply|destroy]
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
STACK_DIR="${SCRIPT_DIR}"
CONFIG_FILE="${REPO_ROOT}/config/shared.auto.tfvars.json"
die() { echo "ERROR: $*" >&2; exit 1; }

###############################################################################
# Parse action
###############################################################################
ACTION="${1:-plan}"
case "${ACTION}" in
  plan|apply|destroy) ;;
  *)
    echo "Usage: bash terragrunt/live/aws/iam-setup/iam-setup.sh [plan|apply|destroy]"
    exit 1
    ;;
esac

[[ -f "${STACK_DIR}/terragrunt.stack.hcl" ]] || die "Stack not found: ${STACK_DIR}/terragrunt.stack.hcl"
[[ -f "${CONFIG_FILE}" ]] || die "Config not found: ${CONFIG_FILE}"
command -v terragrunt >/dev/null 2>&1 || die "terragrunt is not installed."

echo "Using config: ${CONFIG_FILE}"

# Terragrunt stacks execute multiple Terraform roots. A global TF_DATA_DIR makes
# those roots share backend metadata and local locks, so keep metadata per unit.
unset TF_DATA_DIR

cd "${STACK_DIR}"
exec terragrunt stack run "${ACTION}"
