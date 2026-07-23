#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
STACK_DIR="${REPO_ROOT}/terragrunt/live/aws/operators-iam"
UNIT_DIR="${STACK_DIR}/.terragrunt-stack/aws-csoc-operator-iam"
CONFIG_FILE="${REPO_ROOT}/config/shared.auto.tfvars.json"
OUTPUT_FILE="${REPO_ROOT}/outputs/aws-csoc-operator-iam.json"

for command in terragrunt jq; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "FATAL: ${command} is required." >&2
    exit 1
  }
done

[[ -f "$CONFIG_FILE" ]] || {
  echo "FATAL: missing ${CONFIG_FILE}" >&2
  exit 1
}

(cd "$STACK_DIR" && terragrunt stack generate >/dev/null)

[[ -d "$UNIT_DIR" ]] || {
  echo "FATAL: generated operator unit not found: ${UNIT_DIR}" >&2
  exit 1
}

role_arns="$(cd "$UNIT_DIR" && terragrunt output -json role_arns)"
default_role_key="$(cd "$UNIT_DIR" && terragrunt output -raw default_role_key)"
mfa_device_arns="$(cd "$UNIT_DIR" && terragrunt output -json mfa_device_arns)"
source_profile="$(jq -r '.aws_profile // empty' "$CONFIG_FILE")"

mkdir -p "$(dirname "$OUTPUT_FILE")"
temp_file="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"
trap 'rm -f "$temp_file"' EXIT

jq -n \
  --arg source_profile "$source_profile" \
  --arg default_role_key "$default_role_key" \
  --argjson role_arns "$role_arns" \
  --argjson mfa_device_arns "$mfa_device_arns" \
  '{
    source_profile: $source_profile,
    default_role_key: $default_role_key,
    role_arns: $role_arns,
    mfa_device_arns: $mfa_device_arns
  }' > "$temp_file"

chmod 0600 "$temp_file"
mv "$temp_file" "$OUTPUT_FILE"
trap - EXIT

echo "Wrote ${OUTPUT_FILE}"
