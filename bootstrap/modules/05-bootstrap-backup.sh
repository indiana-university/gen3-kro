#!/usr/bin/env bash
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Backup the bootstrap folder
#-------------------------------------------------------------------------------------------------------------------------------------------------#
set -euo pipefail

: "${WORKING_REPO:?WORKING_REPO must be set}"
: "${BOOT_DIR:?BOOT_DIR must be set (bootstrap destination)}"
: "${DIFF_LOG:=outputs/diff.log}"

IFS=$'\n\t'

# Pass 1: Copy new or changed files from working → bootstrap
find "$WORKING_REPO/$(basename "$BOOT_DIR")" -type f -print0 |
while IFS= read -r -d '' src; do
  rel_path=${src#"$WORKING_REPO/$(basename "$BOOT_DIR")/"}
  dst="$BOOT_DIR/$rel_path"

  # If bootstrap file missing, or content differs → copy it over
  if [[ ! -f "$dst" ]] || ! diff -u --strip-trailing-cr -b -B "$src" "$dst" >> "$DIFF_LOG"; then
    printf 'Updating %s in bootstrap\n' "$rel_path"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
done

# Pass 2: Delete stale files from bootstrap
find "$BOOT_DIR" -type f -print0 |
while IFS= read -r -d '' dst; do
  rel_path=${dst#"$BOOT_DIR/"}
  src="$WORKING_REPO/$(basename "$BOOT_DIR")/$rel_path"

  # If working copy missing, or content differs → delete from bootstrap
  if [[ ! -f "$src" ]] || ! diff -u --strip-trailing-cr -b -B "$src" "$dst" >> "$DIFF_LOG"; then
    printf 'Deleting %s from bootstrap\n' "$rel_path"
    rm -f "$dst"
  fi
done

# Pass 3: Remove any empty dirs left in bootstrap
find "$BOOT_DIR" -type d -empty -delete
###################################################################################################################################################
# End of Script
###################################################################################################################################################
