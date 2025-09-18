#!/usr/bin/env bash
###################################################################################################################################################
# Synchronize templates into the working repo
###################################################################################################################################################
# shellcheck disable=SC2154
# functions for repository file management

: "${DIFF_LOG:=$OUTPUTS_DIR/diff.log}"
: "${WORKING_DIR:=$LOCAL_WORKING_DIR}"
: "${TEMPLATES_DIR:=$TEMPLATES_DIR}"
: "${TF_DEV_DEST:=$TF_DEV_DEST}"
: "${TF_STAGING_DEST:=$TF_STAGING_DEST}"
: "${TF_PROD_DEST:=$TF_PROD_DEST}"
: > "$DIFF_LOG"  # clear diff log

#---------------------------------------------------------------------------------------------------------------------------------------------------#
# Main script
#---------------------------------------------------------------------------------------------------------------------------------------------------#
log "#------------------------------------------------------------------------------------------------------------#"
# remove_non_existent_files "$TEMPLATES_DIR/argocd"    "$WORKING_DIR/argocd"

remove_non_existent_files "$TEMPLATES_DIR/apps"     "$WORKING_DIR/apps"
remove_non_existent_files "$TEMPLATES_DIR/addons"   "$WORKING_DIR/addons"
remove_non_existent_files "$TEMPLATES_DIR/charts"   "$WORKING_DIR/charts"
remove_non_existent_files "$TEMPLATES_DIR/fleet"    "$WORKING_DIR/fleet"
remove_non_existent_files "$TEMPLATES_DIR/platform" "$WORKING_DIR/platform"

log "#------------------------------------------------------------------------------------------------------------#"
update_from_template "$TEMPLATES_DIR/apps"     "$WORKING_DIR/apps"
update_from_template "$TEMPLATES_DIR/addons"   "$WORKING_DIR/addons"
update_from_template "$TEMPLATES_DIR/charts"   "$WORKING_DIR/charts"
update_from_template "$TEMPLATES_DIR/fleet"    "$WORKING_DIR/fleet"
update_from_template "$TEMPLATES_DIR/platform" "$WORKING_DIR/platform"

log_info "Sync complete. Diff log: $DIFF_LOG"
log "#------------------------------------------------------------------------------------------------------------#"
