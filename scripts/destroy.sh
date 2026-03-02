#!/usr/bin/env bash
###############################################################################
# Destroy Script — CSOC EKS Stack (Plain Terraform)
#
# Tears down the entire CSOC environment provisioned by terraform/env/aws/csoc-cluster/
# and cleans up local state (kubeconfig, output files, port-forwards).
#
# Steps:
#   1. Kill ArgoCD port-forwards
#   2. Terraform destroy (EKS, VPC, IAM)
#   3. Clean kubeconfig
#   4. Clean output files
#   5. Clean local terraform artifacts
#
# Usage:
#   bash destroy.sh
#
# All output is logged to outputs/logs/destroy-<timestamp>.log
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
LOG_FILE="${LOG_DIR}/destroy-${TIMESTAMP}.log"

###############################################################################
# Helpers
###############################################################################
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

die() {
  log "FATAL: $*"
  exit 1
}

# When TF_DATA_DIR is set (container environment), run terraform from a
# container-local directory that symlinks back to the real .tf files.
# Also symlinks shared.auto.tfvars.json for auto-load.
setup_workdir() {
  if [[ -z "${TF_DATA_DIR:-}" ]]; then
    WORK_DIR="$ENV_DIR"
  else
    WORK_DIR="/home/vscode/.terraform-workdir/terraform/env/aws/csoc-cluster"
    mkdir -p "$WORK_DIR"
    for f in "${ENV_DIR}"/*.tf; do
      [[ -f "$f" ]] && ln -sfn "$f" "$WORK_DIR/$(basename "$f")"
    done
    ln -sfn "${REPO_ROOT}/terraform/catalog" "/home/vscode/.terraform-workdir/terraform/catalog"
    log "  WORK_DIR: $WORK_DIR  (container-local, TF_DATA_DIR=${TF_DATA_DIR})"
  fi
  ln -sfn "$CONFIG_FILE" "$WORK_DIR/shared.auto.tfvars.json"
}

###############################################################################
# Step 1: Determine cluster name
###############################################################################
resolve_cluster_name() {
  CLUSTER_NAME=""

  # Read from terraform output (most accurate when state exists)
  local tf_dir="${TF_DATA_DIR:-${ENV_DIR}/.terraform}"
  if [[ -d "$tf_dir" ]]; then
    setup_workdir
    CLUSTER_NAME="$(cd "$WORK_DIR" && terraform output -raw cluster_name 2>/dev/null)" || CLUSTER_NAME=""
  fi

  # Fallback: derive from csoc_alias in config JSON (csoc_alias + "-csoc-cluster")
  if [[ -z "$CLUSTER_NAME" && -f "${CONFIG_FILE}" ]]; then
    local csoc_alias
    csoc_alias="$(jq -r '.csoc_alias // empty' "${CONFIG_FILE}" 2>/dev/null)" || csoc_alias=""
    if [[ -n "$csoc_alias" ]]; then
      CLUSTER_NAME="${csoc_alias}-csoc-cluster"
    else
      # Legacy fallback: direct cluster_name field
      CLUSTER_NAME="$(jq -r '.cluster_name // empty' "${CONFIG_FILE}" 2>/dev/null)" || CLUSTER_NAME=""
    fi
  fi

  log "Cluster name: ${CLUSTER_NAME:-<not found>}"
}

###############################################################################
# Step 2: Kill ArgoCD port-forwards
###############################################################################
kill_port_forwards() {
  log ""
  log ">>> [Step 1/5] Stopping any ArgoCD port-forwards..."

  # Kill by port-forward pattern for argocd (covers any cluster name)
  pkill -f "kubectl port-forward.*argocd" 2>/dev/null || true

  # Also kill by cluster name if known
  if [[ -n "${CLUSTER_NAME:-}" ]]; then
    pkill -f "port-forward.*${CLUSTER_NAME}" 2>/dev/null || true
  fi

  log "  Port-forwards stopped."
}

###############################################################################
# Step 2: Terraform destroy
###############################################################################
terraform_destroy() {
  log ""
  log ">>> [Step 2/5] Running terraform destroy..."

  if [[ ! -d "$ENV_DIR" ]]; then
    die "Terraform env directory not found: ${ENV_DIR}"
  fi

  setup_workdir
  cd "$WORK_DIR"

  # Validate config file
  if [[ ! -f "$CONFIG_FILE" ]]; then
    die "shared.auto.tfvars.json not found at ${CONFIG_FILE}."
  fi

  # Extract backend config from the shared JSON
  local backend_bucket backend_key backend_region
  backend_bucket="$(jq -r '.backend_bucket // empty' "$CONFIG_FILE")"
  backend_key="$(jq -r '.backend_key // empty' "$CONFIG_FILE")"
  backend_region="$(jq -r '.backend_region // empty' "$CONFIG_FILE")"

  if [[ -z "$backend_bucket" || -z "$backend_key" || -z "$backend_region" ]]; then
    die "backend_bucket, backend_key, and backend_region must be set in ${CONFIG_FILE}"
  fi

  log "  Running terraform init (required before destroy)..."
  log "  TF_DATA_DIR: ${TF_DATA_DIR:-<not set>}"
  terraform init \
    -backend-config="bucket=${backend_bucket}" \
    -backend-config="key=${backend_key}" \
    -backend-config="region=${backend_region}"

  local destroy_start destroy_end rc=0
  destroy_start="$(date +%s)"

  terraform destroy -auto-approve || rc=$?

  destroy_end="$(date +%s)"
  if [[ $rc -ne 0 ]]; then
    log ">>> Terraform destroy FAILED (exit ${rc}) after $(( destroy_end - destroy_start ))s"
    return $rc
  fi
  log ">>> Terraform destroy completed in $(( destroy_end - destroy_start ))s"
}

###############################################################################
# Step 3: Clean kubeconfig
###############################################################################
clean_kubeconfig() {
  log ""
  log ">>> [Step 3/5] Cleaning kubeconfig..."

  if [[ -n "${CLUSTER_NAME:-}" ]]; then
    kubectl config unset "users.${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config unset "clusters.${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config delete-context "${CLUSTER_NAME}" 2>/dev/null || true

    # Also try ARN-style contexts that EKS update-kubeconfig creates
    local region
    region="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"

    # Remove any matching context/cluster/user entries
    for ctx in $(kubectl config get-contexts -o name 2>/dev/null | grep "${CLUSTER_NAME}" || true); do
      kubectl config delete-context "$ctx" 2>/dev/null || true
    done
    for cl in $(kubectl config get-clusters 2>/dev/null | grep "${CLUSTER_NAME}" || true); do
      kubectl config unset "clusters.${cl}" 2>/dev/null || true
    done

    log "  Removed ${CLUSTER_NAME} from kubeconfig."
  else
    log "  Could not determine cluster name — skipping kubeconfig cleanup."
  fi
}

###############################################################################
# Step 4: Clean output files
###############################################################################
clean_outputs() {
  log ""
  log ">>> [Step 4/5] Cleaning output files..."

  rm -f "${OUTPUTS_DIR}/connect-csoc.sh"
  rm -f "${OUTPUTS_DIR}/argocd-password.txt"
  rm -f "${ENV_DIR}/connect-csoc.sh"

  log "  Output files cleaned."
}

###############################################################################
# Step 5: Clean terraform local state artifacts
###############################################################################
clean_terraform_local() {
  log ""
  log ">>> [Step 5/5] Cleaning local terraform artifacts..."

  # Remove .terraform directory (state is in S3; lock file is preserved)
  rm -rf "${ENV_DIR}/.terraform"
  # Also clean container-local TF_DATA_DIR and workdir if they exist
  rm -rf "/home/vscode/.terraform-data" 2>/dev/null || true
  rm -rf "/home/vscode/.terraform-workdir" 2>/dev/null || true

  log "  Local terraform artifacts removed."
}

###############################################################################
# Main
###############################################################################
main() {
  log "============================================="
  log " CSOC Stack Destroy"
  log " Env Dir:  ${ENV_DIR}"
  log " Log:      ${LOG_FILE}"
  log " Started:  $(date)"
  log "============================================="

  resolve_cluster_name
  kill_port_forwards
  terraform_destroy
  clean_kubeconfig
  clean_outputs
  clean_terraform_local

  log ""
  log "============================================="
  log " Destroy complete — $(date)"
  log " Log saved to: ${LOG_FILE}"
  log "============================================="
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
