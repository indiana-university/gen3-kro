#!/usr/bin/env bash
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Global configuration for the bootstrap workflow.
# This file is sourced by driver.sh and (optionally) reloaded by functions.sh.
# Set RUN_MODE and any LOG_* / EXEC_* overrides here.
#-------------------------------------------------------------------------------------------------------------------------------------------------#
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 1) Behavior / Mode
#-------------------------------------------------------------------------------------------------------------------------------------------------#MAIN_PROMPT_TIMEOUT_SECS=60            # start pipeline prompt
MAIN_LOOP_TIMEOUT_SECS=10               # start pipeline prompt
STEP_TIMEOUT_SECS=10                  # per-step prompt
STEP_RETRY_TIMEOUT_SECS=600           # retry prompt
VAL_TIMEOUT_SECS=10                     # validation retry prompt
MAX_CYCLE_RETRIES=10                    # max retries on cycle
MAX_MODULE_RETRIES=50                   # max retries on module
MAX_VALIDATION_RETRIES=60               # max retries on validation
# Optional: fine-grained overrides (all optional; apply_mode sets sane defaults)
# Examples (uncomment to use):
#   export LOG_LEVEL="ERROR"          # force only errors (even in info/json)
#   export LOG_FORMAT="json"          # override output format
#   export LOG_TO_STDERR=1            # log to console
#   export LOG_TO_FILE=1              # also log to file
#   export LOG_FILE="${OUTPUTS_DIR:-outputs}/run.log"
#   export LOG_COLOR="never"          # never colorize
#   export RUN_DEBUG=1                # force reload_env() between steps, regardless of mode

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 2) Terraform
#-------------------------------------------------------------------------------------------------------------------------------------------------#
TERRAFORM_MODE=validate   # terraform mode: create | destroy | plan | validate

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# 3) Execution
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# - EXEC_MODE_DEFAULT (ask|auto) is set by RUN_MODE (ask in info/debug/json, auto in quiet/batch)
#   but you can force it here if you want:
#   example: export EXEC_MODE_DEFAULT=(auto|ask)

# - STEPS_EXEC_MODE is an associative array of per-step execution modes (ask|auto).
#   example: STEPS_EXEC_MODE["01-init-repo.sh"]="ask"
declare -A -g STEPS_EXEC_MODE=(
  ["00-validations.sh"]="auto"
  ["01-backups.sh"]="auto"
  ["02-update-files.sh"]="auto"
  ["04-terraform.sh"]="auto"
  # ["04-terraform.sh"]=""
  # ["05-bootstrap-backup.sh"]=""
  # ["06-setup-argocd.sh"]=""
)

# DEBUG_MODE_FILES is an indexed array of env files to load in debug mode, in order.
#   example: ##|<folder>/<file>
declare -ag DEBUG_MODE_FILES=(
  "00|$AUTOMATION_DIR/customize.env"
  "01|$BIN_DIR/functions.sh"
  "03|$BIN_DIR/settings.sh"
)

# Default environment files to load in all modes, in order.
#   example: ##|<folder>/<file>
declare -ag DEFAULT_FILES=(
  "02|$ENV_DIR/aws.env"
  "03|$ENV_DIR/hub.env"
  "04|$ENV_DIR/spoke.env"
  "05|$ENV_DIR/folders.env"
  "06|$ENV_DIR/files.env"
  "07|$ENV_DIR/output.env"
  "08|$ENV_DIR/gitops.env"
)

# Required by 01-init-repo.sh
declare -ag CONTROLLERS=(
  iam
  eks
  ec2
  efs
)
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Export key variables for use by other scripts
#-------------------------------------------------------------------------------------------------------------------------------------------------#
export MAIN_LOOP_TIMEOUT_SECS
export STEP_TIMEOUT_SECS
export STEP_RETRY_TIMEOUT_SECS
export VAL_TIMEOUT_SECS
export MAX_CYCLE_RETRIES
export MAX_MODULE_RETRIES
export MAX_VALIDATION_RETRIES
export TERRAFORM_MODE
export STEPS_EXEC_MODE
export DEBUG_MODE_FILES
export DEFAULT_FILES
export CONTROLLERS

###################################################################################################################################################
# End of file 
###################################################################################################################################################