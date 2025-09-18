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
: "${TF_ENV_DEST:=$TF_ENV_DEST}"     # must be set in env file
: "${DESTINATION_REPO:=$DESTINATION_REPO}" # required
: "${HUB_CLUSTER_NAME:=$HUB_CLUSTER_NAME}" # required
: "${AUTOMATION_DIR:=$AUTOMATION_DIR}" # must be set in env file
: "${REFRESH_LOG_FILE:=1}"           
: "${RUN_LOG_FILE:=$OUTPUTS_DIR/terraform_cmd.log}" # log file for stderr of terraform commands
: "${CONTROLLERS:=$CONTROLLERS}" # comma-separated list of ACK controllers to enable
: > "$RUN_LOG_FILE"  # clear logfile

: "${DIFF_LOG:=$OUTPUTS_DIR/diff.log}"
: "${TEMPLATES_DIR:=$TEMPLATES_DIR}"
: "${TF_DEV_DEST:=$TF_DEV_DEST}"
: "${TF_STAGING_DEST:=$TF_STAGING_DEST}"
: "${TF_PROD_DEST:=$TF_PROD_DEST}"
: > "$DIFF_LOG"  # clear diff log

#---------------------------------------------------------------------------------------------------------------------------------------------------#
# Main script
#---------------------------------------------------------------------------------------------------------------------------------------------------#
log "#------------------------------------------------------------------------------------------------------------#"
update_from_template "$TEMPLATES_DIR/terraform" "$LOCAL_WORKING_DIR/terraform"

log_info "Sync complete. Diff log: $DIFF_LOG"
log "#------------------------------------------------------------------------------------------------------------#"
init_management_cluster

###################################################################################################################################################
# End of script
###################################################################################################################################################
