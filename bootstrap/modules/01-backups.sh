#!/usr/bin/env bash
###################################################################################################################################################
# Repo Setup (sourced by driver.sh)
# - Idempotent bootstrap for a local working dir and a destination GitHub repo.
# - Keeps caller's worktree logic (sed edit to core.worktree) intact.
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# prepare workspace
#-------------------------------------------------------------------------------------------------------------------------------------------------#
prep_workspace() {

  # Move .git folder to designated location (as per your prior design)
  log "#-----------------------------------------------------------------------------------------------------------#"
  log_info "[prep_workspace():.git LOCAL_WORKING_DIR=$LOCAL_WORKING_DIR AUTOMATION_DIR=$AUTOMATION_DIR]"
  if [[ -d "$LOCAL_WORKING_DIR/.git" ]]; then
    if ! backup_path ".git"; then return 1; fi
    rm -rf ".git" || { log_error "Failed to remove existing .git in automation dir"; return 1; }
    mv "$LOCAL_WORKING_DIR/.git" "." || { log_error "Failed to move .git to automation dir"; return 1; }
    sed -i.bak "/\[core\]/a\\"$'\n\t'"worktree = ../$LOCAL_WORKING_DIR" .git/config || { log_error "Failed to update core.worktree in .git/config"; return 1; }
    log_notice "[Moved .git to automation dir; worktree set to $LOCAL_WORKING_DIR]"
  fi

  if ! backup_path "$AUTOMATION_DIR"; then return 1; fi
  log_notice "[prep_workspace()] completed successfully"
  log "#-----------------------------------------------------------------------------------------------------------#"
  }

#-------------------------------------------------------------------------------------------------------------------------------------------------#
prep_workspace
#-------------------------------------------------------------------------------------------------------------------------------------------------#
###################################################################################################################################################
# End of script
###################################################################################################################################################