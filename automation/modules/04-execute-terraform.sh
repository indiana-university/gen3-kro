#!/usr/bin/env bash
###################################################################################################################################################
# Initialize Management Cluster with Terraform
###################################################################################################################################################
set -euo pipefail
IFS=$'\n\t'

# Derived paths (use absolute paths to avoid pushd/popd path math)
: "${DESTINATION_REPO:?DESTINATION_REPO must be set}"
: "${ENVIRONMENT:?ENVIRONMENT must be set (e.g., dev|staging|prod)}"
: "${OUTPUTS_DIR:=outputs}"
: "${CREATE_INFRASTRUCTURE:=0}"         # 1=apply, 0=destroy
: "${TF_VAR_FILE:?TF_VAR_FILE must point to a valid -var-file}"
: "${HUB_PROFILE:?HUB_PROFILE must be set}"
: "${HUB_CLUSTER_NAME:?HUB_CLUSTER_NAME must be set}"

HUB_DIR="$DESTINATION_REPO/terraform/hubs/$ENVIRONMENT/${HUB_PROFILE}/${HUB_CLUSTER_NAME}"
OUT_TF_DIR="$OUTPUTS_DIR/terraform"
PLAN_BIN="$OUT_TF_DIR/tfplan.bin"
PLAN_JSON="$OUT_TF_DIR/plan.json"
[[ -d "$HUB_DIR" ]] || die 121 "Terraform working dir not found: $HUB_DIR"
[[ -f "$TF_VAR_FILE" ]] || die 122 "TF_VAR_FILE does not exist: $TF_VAR_FILE"
mkdir -p "$OUT_TF_DIR"
rc=$?

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Initialize Terraform in the target working directory
#-------------------------------------------------------------------------------------------------------------------------------------------------#
if (( rc == 0 )); then
  terraform -chdir="$HUB_DIR" init -input=false
  rc=$?
fi

#-----------------------------------------------------------------------------------------------------------------------------------------------#
# Plan and apply Terraform configuration
#-----------------------------------------------------------------------------------------------------------------------------------------------#
if [[ "$CREATE_INFRASTRUCTURE" -eq 1 ]]; then
  if (( rc == 0 )); then
    terraform -chdir="$HUB_DIR" plan -input=false -out="$PLAN_BIN" -var-file="$TF_VAR_FILE"
  fi
  rc=$?
  if (( rc == 0 )); then
    terraform -chdir="$HUB_DIR" show -json "$PLAN_BIN" > "$PLAN_JSON"
  fi
  # Optional lightweight summary for quick inspection
  if command -v jq >/dev/null 2>&1; then
    jq -r '.resource_changes[]?| [.address, .change.actions|join(",")] | @tsv' "$PLAN_JSON" \
      > "$OUT_TF_DIR/plan.summary.tsv" || true
  fi
  rc=$?
  if (( rc == 0 )); then
    terraform -chdir="$HUB_DIR" apply -auto-approve "$PLAN_BIN"
  fi
else
  if (( rc == 0 )); then
    terraform -chdir="$HUB_DIR" destroy -var-file="$TF_VAR_FILE" -refresh=false -auto-approve
  fi
fi

exit $rc

###################################################################################################################################################
# End of script
###################################################################################################################################################
