#!/usr/bin/env bash
###############################################################################
# CSOC Split-State Migration Helper
#
# Moves Terraform state from legacy entrypoints into the Terragrunt-first split
# state layout without applying resources. The script is intentionally gated and
# requires explicit confirmation because it mutates backend state.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
CONFIG_FILE="${REPO_ROOT}/config/shared.auto.tfvars.json"
LEGACY_ROOT="${REPO_ROOT}/terraform/env/aws/csoc-cluster"
CSOC_STACK="${REPO_ROOT}/terragrunt/live/aws/csoc"
IAM_SETUP_STACK="${REPO_ROOT}/terragrunt/live/aws/iam-setup"
WORK_DIR="${REPO_ROOT}/outputs/state-migration"
CONFIRM="${CONFIRM_STATE_MIGRATION:-}"

usage() {
  cat <<USAGE
Usage: CONFIRM_STATE_MIGRATION=yes bash scripts/state-migration.sh

This performs state-only migration. It does not run terraform apply.

Required preconditions:
  - terraform, terragrunt, aws, and jq are installed.
  - AWS credentials can access the configured S3 backend.
  - The legacy compatibility root plan has been reviewed.
  - The new Terragrunt CSOC stack plan has been reviewed.
  - Those plans show no creates, deletes, replacements, or unintended updates.

Destination state keys:
  - csoc/foundation/terraform.tfstate
  - csoc/in-cluster-bootstrap/terraform.tfstate
  - csoc/spoke-iam/terraform.tfstate

Developer identity stays at:
  - iam-setup/developer-identity/terraform.tfstate
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "FATAL: required command not found: $cmd" >&2
    exit 1
  fi
}

json_value() {
  local expr="$1"
  jq -r "$expr // empty" "$CONFIG_FILE"
}

state_has_address() {
  local state_file="$1"
  local address="$2"
  terraform state list -state="$state_file" | grep -Fxq "$address"
}

move_if_present() {
  local source_state="$1"
  local dest_state="$2"
  local from="$3"
  local to="$4"

  if state_has_address "$dest_state" "$to"; then
    echo "SKIP: destination already exists: $to"
    return 0
  fi

  if state_has_address "$source_state" "$from"; then
    echo "MOVE: $from -> $to"
    terraform state mv \
      -state="$source_state" \
      -state-out="$dest_state" \
      "$from" \
      "$to"
  else
    echo "SKIP: source not present: $from"
  fi
}

pull_state() {
  local unit_dir="$1"
  local output_file="$2"

  (
    cd "$unit_dir"
    terraform state pull > "$output_file"
  )
}

empty_state() {
  local output_file="$1"
  local lineage
  lineage="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  cat > "$output_file" <<STATE
{
  "version": 4,
  "terraform_version": "1.13.5",
  "serial": 0,
  "lineage": "${lineage}",
  "outputs": {},
  "resources": [],
  "check_results": null
}
STATE
}

pull_state_or_empty() {
  local unit_dir="$1"
  local output_file="$2"

  if ! pull_state "$unit_dir" "$output_file"; then
    echo "WARN: no remote state found for $unit_dir; using empty local destination state."
    empty_state "$output_file"
  fi
}

push_state() {
  local unit_dir="$1"
  local input_file="$2"

  (
    cd "$unit_dir"
    terraform state push "$input_file"
  )
}

require_generated_unit() {
  local unit_dir="$1"
  if [[ ! -d "$unit_dir" ]]; then
    echo "FATAL: generated Terragrunt unit not found: $unit_dir" >&2
    echo "Run: cd $CSOC_STACK && terragrunt stack generate" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

if [[ "$CONFIRM" != "yes" ]]; then
  usage >&2
  echo "FATAL: set CONFIRM_STATE_MIGRATION=yes to execute state moves." >&2
  exit 1
fi

require_cmd terraform
require_cmd terragrunt
require_cmd aws
require_cmd jq

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "FATAL: config file not found: $CONFIG_FILE" >&2
  exit 1
fi

BACKEND_BUCKET="$(json_value '.backend_bucket')"
BACKEND_REGION="$(json_value '.backend_region')"
AWS_PROFILE_NAME="$(json_value '.aws_profile')"

if [[ -z "$BACKEND_BUCKET" || -z "$BACKEND_REGION" || -z "$AWS_PROFILE_NAME" ]]; then
  echo "FATAL: backend_bucket, backend_region, and aws_profile must be set in config." >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR" 2>/dev/null || true

echo ">>> Validating backend access"
aws sts get-caller-identity --profile "$AWS_PROFILE_NAME" >/dev/null
aws s3api head-bucket --bucket "$BACKEND_BUCKET" --profile "$AWS_PROFILE_NAME" >/dev/null

echo ">>> Generating Terragrunt stack units"
(
  cd "$CSOC_STACK"
  terragrunt stack generate
)

CSOC_GENERATED="${CSOC_STACK}/.terragrunt-stack"
FOUNDATION_UNIT="${CSOC_GENERATED}/csoc-foundation"
BOOTSTRAP_UNIT="${CSOC_GENERATED}/csoc-in-cluster-bootstrap"
SPOKE_IAM_UNIT="${CSOC_GENERATED}/spoke-iam"
IAM_SETUP_GENERATED="${IAM_SETUP_STACK}/.terragrunt-stack"
LEGACY_SPOKE_UNIT="${IAM_SETUP_GENERATED}/aws-spoke"

require_generated_unit "$FOUNDATION_UNIT"
require_generated_unit "$BOOTSTRAP_UNIT"
require_generated_unit "$SPOKE_IAM_UNIT"

echo ">>> Initializing source and destination backends"
bash "${REPO_ROOT}/scripts/install.sh" init
(
  cd "$FOUNDATION_UNIT"
  terraform init -reconfigure
)
(
  cd "$BOOTSTRAP_UNIT"
  terraform init -reconfigure
)
(
  cd "$SPOKE_IAM_UNIT"
  terraform init -reconfigure
)

if [[ -d "$LEGACY_SPOKE_UNIT" ]]; then
  (
    cd "$LEGACY_SPOKE_UNIT"
    terraform init -reconfigure
  )
else
  echo "WARN: legacy spoke IAM generated unit not found; spoke state copy will be skipped."
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LEGACY_STATE="${WORK_DIR}/legacy-csoc-${TIMESTAMP}.tfstate"
FOUNDATION_STATE="${WORK_DIR}/foundation-${TIMESTAMP}.tfstate"
BOOTSTRAP_STATE="${WORK_DIR}/bootstrap-${TIMESTAMP}.tfstate"
SPOKE_STATE="${WORK_DIR}/spoke-iam-${TIMESTAMP}.tfstate"

echo ">>> Pulling backend states to local migration workspace"
pull_state "$LEGACY_ROOT" "$LEGACY_STATE"
pull_state_or_empty "$FOUNDATION_UNIT" "$FOUNDATION_STATE"
pull_state_or_empty "$BOOTSTRAP_UNIT" "$BOOTSTRAP_STATE"
pull_state_or_empty "$SPOKE_IAM_UNIT" "$SPOKE_STATE"

echo ">>> Moving CSOC foundation addresses"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.module.eks" "module.eks"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.module.vpc" "module.vpc"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.module.external_secrets_pod_identity" "module.external_secrets_pod_identity"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role.ack_csoc_source" "aws_iam_role.ack_csoc_source"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_entry.ack_csoc_source" "aws_eks_access_entry.ack_csoc_source"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_policy_association.ack_csoc_source_admin" "aws_eks_access_policy_association.ack_csoc_source_admin"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_capability.ack" "aws_eks_capability.ack"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role_policy.ack_csoc_assume_spoke" "aws_iam_role_policy.ack_csoc_assume_spoke"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role.kro_controller" "aws_iam_role.kro_controller"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_entry.kro_controller" "aws_eks_access_entry.kro_controller"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_policy_association.kro_controller_admin" "aws_eks_access_policy_association.kro_controller_admin"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_capability.kro" "aws_eks_capability.kro"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role.argocd_controller" "aws_iam_role.argocd_controller"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_entry.argocd_controller" "aws_eks_access_entry.argocd_controller"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_access_policy_association.argocd_controller_admin" "aws_eks_access_policy_association.argocd_controller_admin"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_eks_capability.argocd" "aws_eks_capability.argocd"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role.argocd_self_managed" "aws_iam_role.argocd_self_managed"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role_policy.argocd_assume_spoke" "aws_iam_role_policy.argocd_assume_spoke"
move_if_present "$LEGACY_STATE" "$FOUNDATION_STATE" "module.csoc_cluster.module.aws_csoc.aws_iam_role_policy.argocd_inline" "aws_iam_role_policy.argocd_inline"

echo ">>> Moving in-cluster bootstrap addresses"
move_if_present "$LEGACY_STATE" "$BOOTSTRAP_STATE" "module.csoc_cluster.module.aws_csoc.kubernetes_namespace_v1.argocd" "kubernetes_namespace_v1.argocd"
move_if_present "$LEGACY_STATE" "$BOOTSTRAP_STATE" "module.csoc_cluster.module.aws_csoc.kubernetes_service_account_v1.argocd" "kubernetes_service_account_v1.argocd"
move_if_present "$LEGACY_STATE" "$BOOTSTRAP_STATE" "module.csoc_cluster.module.aws_csoc.kubernetes_service_account_v1.argocd_controller" "kubernetes_service_account_v1.argocd_controller"
move_if_present "$LEGACY_STATE" "$BOOTSTRAP_STATE" "module.csoc_cluster.module.aws_csoc.helm_release.argocd" "helm_release.argocd"
move_if_present "$LEGACY_STATE" "$BOOTSTRAP_STATE" "module.csoc_cluster.module.argocd_bootstrap" "module.argocd_bootstrap"

if [[ -d "$LEGACY_SPOKE_UNIT" ]]; then
  echo ">>> Copying spoke IAM state into CSOC spoke-iam state key"
  pull_state "$LEGACY_SPOKE_UNIT" "$SPOKE_STATE"
else
  echo ">>> Skipping spoke IAM state copy"
fi

echo ">>> Pushing destination states"
push_state "$FOUNDATION_UNIT" "$FOUNDATION_STATE"
push_state "$BOOTSTRAP_UNIT" "$BOOTSTRAP_STATE"
push_state "$SPOKE_IAM_UNIT" "$SPOKE_STATE"

echo ">>> Pushing legacy CSOC source state with moved resources removed"
push_state "$LEGACY_ROOT" "$LEGACY_STATE"

echo ">>> State migration complete."
echo "Next required no-apply validation:"
echo "  bash scripts/csoc-stack.sh plan"
echo "  bash scripts/install.sh plan"
