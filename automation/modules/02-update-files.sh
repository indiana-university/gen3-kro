#!/usr/bin/env bash
###################################################################################################################################################
# Synchronize templates into the working repo
###################################################################################################################################################
# shellcheck disable=SC2154
# functions for repository file management
: "${DIFF_LOG:=$OUTPUTS_DIR/diff.log}"
: "${WORKING_DIR:=$LOCAL_WORKING_DIR}"
: "${SYNC_DIRS:=$SYNC_DIRS}"
: "${TF_MODULES_TEMPLATES:=$TF_MODULES_TEMPLATES}"
: "${TF_MODULES_FILES:=$TF_MODULES_FILES}"
remove_paths() {
  [[ -n "${WORKING_DIR:-}" ]] ||  { log_error "WORKING_DIR is not set"; return 1; }
  local p
  for p in "$@"; do
    rm -rf -- "$WORKING_DIR/${p:?}"
    log_warn "Removed path: $p"
  done
}
update_from_template() {
  local template="$1"; shift || true
  local reldest="$1"; shift || true
  local no_subst_glob="${1:-README.md}" # default skip for README.md

  [[ -f "$template" ]] || { log_error "Template not found: $template"; return 1; }
  [[ -n "${WORKING_DIR:-}" ]] || { log_error "WORKING_DIR is not set"; return 1; }
  local dest="$WORKING_DIR/$reldest"
  mkdir -p "$(dirname -- "$dest")"

  local tmp
  tmp=$(mktemp) || { log_error "mktemp failed"; return 1; }

  local do_subst=0
  if [[ ! "$reldest" == "$no_subst_glob" ]]; then
    if grep -qE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\b' "$template"; then

    # if grep -qE '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?' "$template"; then # '\$\([A-Za-z_][A-Za-z0-9_]*\)'
      do_subst=1
    fi
  fi

  if (( do_subst )); then
    envsubst <"$template" >"$tmp" || { log_error "envsubst failed for $template"; return 1; }
  else
    cp -- "$template" "$tmp"
  fi

  if [[ ! -f "$dest" ]] || ! diff -u --strip-trailing-cr -b -B "$dest" "$tmp" >/dev/null; then
    if [[ -f "$dest" ]]; then
      diff -u --strip-trailing-cr -b -B "$dest" "$tmp" >>"$DIFF_LOG" || true
      chmod --reference="$dest" "$tmp" || true
      log_info "Updated $reldest"
    else
      log_info "Created $reldest"
    fi
    mv -f -- "$tmp" "$dest"
  else
    log_debug "No changes to $reldest"
  fi
  rm -f -- "$tmp"

}

create_dirs() {
  [[ -n "${WORKING_DIR:-}" ]] || { log_error "WORKING_DIR is not set"; return 1; }
  local d
  for d in "$@"; do
    mkdir -p -- "$WORKING_DIR/$d"
    log_debug "Ensured directory: $d"
  done
}

_sync_pairs() {
  local -n src_arr="$1" dst_arr="$2"
  local i
  for i in "${!src_arr[@]}"; do
    update_from_template "${src_arr[$i]}" "${dst_arr[$i]}"
  done
}
#---------------------------------------------------------------------------------------------------------------------------------------------------#
# Main script
#---------------------------------------------------------------------------------------------------------------------------------------------------#
log "#------------------------------------------------------------------------------------------------------------#"
# 5) Terraform content
_sync_pairs HUB_TF_TEMPLATES \
  HUB_TF_FILES
log "#------------------------------------------------------------------------------------------------------------#"
_sync_pairs TF_MODULES_TEMPLATES \
  TF_MODULES_FILES
log "#------------------------------------------------------------------------------------------------------------#"

# # 2) Root metadata files
# update_from_template "$gitignore_content"       "$gitignore_file"       "README.md"
# update_from_template "$gitattributes_content"   "$gitattributes_file"   "README.md"
# update_from_template "$readme_content"          "$readme_file"          "README.md" # README is copied as-is

# # 3) Bulk sync helper (pairs array1/array2 by index)


# # 4) Argo content
# _sync_pairs APPSETS_TEMPLATES   APPSETS_FILES
# _sync_pairs ADDONS_TEMPLATES    ADDONS_FILES
# _sync_pairs HUB_KRO_TEMPLATES   HUB_KRO_FILES
# _sync_pairs SPOKE_KRO_TEMPLATES SPOKE_KRO_FILES
# _sync_pairs CLUSTERS_TEMPLATES  CLUSTERS_FILES
# _sync_pairs PROJECTS_TEMPLATES  PROJECTS_FILES
# _sync_pairs VALUES_TEMPLATES    VALUES_FILES


log_info "Sync complete. Diff log: $DIFF_LOG"
log "#------------------------------------------------------------------------------------------------------------#"
