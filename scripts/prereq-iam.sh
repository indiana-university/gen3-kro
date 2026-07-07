#!/usr/bin/env bash
###############################################################################
# Prerequisite IAM Stack Wrapper
#
# Safe default: plan. This stack contains only developer_identity and cannot
# create the CSOC cluster or spoke IAM resources.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
STACK_DIR="${REPO_ROOT}/terragrunt/live/aws/prereq-iam"
ACTION="${1:-plan}"

usage() {
  cat <<USAGE
Usage: bash scripts/prereq-iam.sh [generate|init|plan|apply|destroy|output]

Commands:
  generate  Generate Terragrunt stack units
  init      Run terragrunt stack init for prerequisite IAM
  plan      Run terragrunt stack plan for prerequisite IAM (default)
  apply     Apply only developer identity prerequisite IAM
  destroy   Destroy only developer identity prerequisite IAM
  output    Show prerequisite IAM stack outputs
USAGE
}

case "$ACTION" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if ! command -v terragrunt >/dev/null 2>&1; then
  echo "FATAL: terragrunt is not installed or not on PATH." >&2
  exit 1
fi

if [[ ! -d "$STACK_DIR" ]]; then
  echo "FATAL: prerequisite IAM stack directory not found: $STACK_DIR" >&2
  exit 1
fi

# Terragrunt stacks execute Terraform roots. A global TF_DATA_DIR can point
# those roots at stale backend metadata, so keep metadata under each unit.
unset TF_DATA_DIR

cd "$STACK_DIR"

case "$ACTION" in
  generate)
    terragrunt stack generate
    ;;
  init|plan|apply|destroy)
    terragrunt stack run "$ACTION"
    ;;
  output)
    terragrunt stack output
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
