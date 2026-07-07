#!/usr/bin/env bash
###############################################################################
# CSOC Terragrunt Stack Wrapper
#
# Safe default: plan. Apply and destroy must be requested explicitly.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
STACK_DIR="${REPO_ROOT}/terragrunt/live/aws/csoc"
ACTION="${1:-plan}"

usage() {
  cat <<USAGE
Usage: bash scripts/csoc-stack.sh [generate|init|plan|apply|destroy|output]

Commands:
  generate  Generate Terragrunt stack units
  init      Run terragrunt stack init
  plan      Run terragrunt stack plan (default)
  apply     Run terragrunt stack apply
  destroy   Run terragrunt stack destroy
  output    Show terragrunt stack outputs
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
  echo "FATAL: CSOC stack directory not found: $STACK_DIR" >&2
  exit 1
fi

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
