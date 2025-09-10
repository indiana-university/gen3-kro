#!/usr/bin/env bash
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# validations for 00-prep-workspace-checks.sh
# - Validates required environment variables and their values before proceeding with automation tasks.
# - Ensures local working directory and automation directory consistency.
# - Checks accessibility of remote Git repositories.
#-------------------------------------------------------------------------------------------------------------------------------------------------#
prep_workspace_checks(){
  local issue=0
  # Required variables
  for var in AUTOMATION_PARENT_DIR LOCAL_WORKING_DIR GITOPS_GITHUB_URL GITHUB_ORG_NAME DESTINATION_REPO DESTINATION_REPO_URL; do
    if ! require_env "$var"; then
      ((issue++))
      log_error "Missing required environment variable: $var"
    fi

    if [[ "$var" == *_DIR ]]; then
      if ! require_dir "$var"; then
        ((issue++))
        log_error "Invalid directory: $var"
      fi
    fi

    if [[ "$var" == *REPO_URL ]]; then
      if ! git ls-remote "${!var}" > /dev/null 2>&1; then
        ((issue++))
        log_error "Cannot access remote git repository: $var, edit repo details in your env files."
      fi
    fi
    
    log "#------------------------------------------------------------------------------------------------------------#"
  done
  
  if (( issue )); then
    log_error "prep_workspace_checks(): failed with $issue issue(s); see prior log entries"
    return 27
  fi

  return 0
}
init_management_cluster_checks() {
  local issue=0
  log_info "[init_management_cluster_checks()=ENVIRONMENT:$ENVIRONMENT Mode: $TERRAFORM_MODE]"

  # Required variables
  for var in DESTINATION_REPO ENVIRONMENT HUB_PROFILE HUB_CLUSTER_NAME hub_tf_dest LOCAL_WORKING_DIR; do
    if ! require_env "$var"; then
      ((issue++))
      log_error "Missing required environment variable: $var"
    fi
  done

  local HUB_DIR="$LOCAL_WORKING_DIR/$hub_tf_dest/$ENVIRONMENT"
  local TF_VAR_FILE

  if [[ "$ENVIRONMENT" == "dev" ]]; then
    TF_VAR_FILE="$HUB_DIR/$HUB_PROFILE.tfvars"
  else
    TF_VAR_FILE="$HUB_DIR/terraform.tfvars"
  fi

  # Pre-checks
  if [[ ! -d "$HUB_DIR" ]]; then
    log_error "Terraform dir not found: $HUB_DIR"
    ((issue++))
  fi

  if [[ ! -f "$TF_VAR_FILE" ]]; then
    log_error "TF_VAR_FILE does not exist: $TF_VAR_FILE"
    ((issue++))
  fi

  mkdir -p "$OUTPUTS_DIR/terraform"

  if (( issue )); then
    log_error "Failed with $issue issue(s); see prior log entries"
    log "#------------------------------------------------------------------------------------------------------------#"
    return 30
  fi
  
  log_notice "[init_management_cluster_checks()] passed"
  log "#------------------------------------------------------------------------------------------------------------#"
  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
prep_workspace_checks
init_management_cluster_checks
###################################################################################################################################################