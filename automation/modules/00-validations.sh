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
#-------------------------------------------------------------------------------------------------------------------------------------------------#
prep_workspace_checks
###################################################################################################################################################