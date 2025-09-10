#!/usr/bin/env bash
###################################################################################################################################################
# Initialize Management Cluster with Terraform
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# - Validates required environment variables and file paths
# - Runs terraform init, plan, apply, destroy, or validate depending on TERRAFORM_MODE
###################################################################################################################################################

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Default values (overridable via environment variables)
#-------------------------------------------------------------------------------------------------------------------------------------------------#
: "${OUTPUTS_DIR:=outputs}"          # Directory to store Terraform outputs
: "${ENVIRONMENT:=staging}"          # dev, staging, production
: "${HUB_PROFILE:=default}"          # Profile for tfvars
: "${LOCAL_WORKING_DIR:=$LOCAL_WORKING_DIR}" # must be set in env file
: "${hub_tf_dest:=$hub_tf_dest}"     # must be set in env file
: "${DESTINATION_REPO:=$DESTINATION_REPO}" # required
: "${HUB_CLUSTER_NAME:=$HUB_CLUSTER_NAME}" # required
: "${TERRAFORM_MODE:=plan}"          # Modes: create | destroy | plan | validate
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Functions
#-------------------------------------------------------------------------------------------------------------------------------------------------#


init_management_cluster() {
  local HUB_DIR="$LOCAL_WORKING_DIR/$hub_tf_dest/$ENVIRONMENT"
  local OUT_TF_DIR="$OUTPUTS_DIR/terraform"
  local PLAN_BIN="$OUT_TF_DIR/tfplan.bin"
  local PLAN_JSON="$OUT_TF_DIR/plan.json"
  local TF_VAR_FILE

  if [[ "$ENVIRONMENT" == "dev" ]]; then
    TF_VAR_FILE="$HUB_DIR/$HUB_PROFILE.tfvars"
  else
    TF_VAR_FILE="$HUB_DIR/terraform.tfvars"
  fi

  log_notice "[init_management_cluster()=HUB_DIR:$HUB_DIR TERRAFORM_MODE: $TERRAFORM_MODE)]"

  if ! run terraform -chdir="$HUB_DIR" init -input=false; then
    log_error "terraform init failed"
    log "------------------------------------------------------------------------------------------------------------"
    return 31
  fi

  case "$TERRAFORM_MODE" in
    create)
      if ! run terraform -chdir="$HUB_DIR" plan -input=false -out="$PLAN_BIN" -var-file="$TF_VAR_FILE"; then
        log_error "Terraform plan failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 32
      fi
      if ! run terraform -chdir="$HUB_DIR" show -json "$PLAN_BIN" > "$PLAN_JSON"; then
        log_error "Terraform show failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 33
      fi

      if command -v jq >/dev/null 2>&1; then
        if ! jq -r '.resource_changes[]?| [.address, .change.actions|join(",")] | @tsv' "$PLAN_JSON" \
          > "$OUT_TF_DIR/plan.summary.tsv"; then
          log_warn "Failed to create plan.summary.tsv"
        fi
      fi

      if ! run terraform -chdir="$HUB_DIR" apply -auto-approve "$PLAN_BIN"; then
        log_error "Terraform apply failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 34
      fi
      log_notice "create completed successfully"
      ;;
    destroy)
      if ! run terraform -chdir="$HUB_DIR" destroy -var-file="$TF_VAR_FILE" -refresh=false -auto-approve; then
        log_error "terraform destroy failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 35
      fi
      log_notice "destroy completed successfully"
      ;;
    plan)
      if ! run terraform -chdir="$HUB_DIR" plan -input=false -var-file="$TF_VAR_FILE" -out="$PLAN_BIN"; then
        log_error "terraform plan failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 36
      fi
      log_notice "plan completed successfully"
      ;;
    validate)
      if ! run terraform -chdir="$HUB_DIR" validate; then
        log_error "terraform validate failed"
        log "------------------------------------------------------------------------------------------------------------"
        return 37
      fi
      log_notice "validate completed successfully"
      ;;
    *)
      log_error "Unknown TERRAFORM_MODE: $TERRAFORM_MODE (expected: create|destroy|plan|validate)"
      log "------------------------------------------------------------------------------------------------------------"
      return 38
      ;;
  esac

  log_notice "[init_management_cluster()] finished"
  log "------------------------------------------------------------------------------------------------------------"

  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
init_management_cluster

###################################################################################################################################################
# End of script
###################################################################################################################################################
