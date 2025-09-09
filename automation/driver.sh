#!/usr/bin/env bash
###################################################################################################################################################
# driver.sh - Main Entry Point
###################################################################################################################################################
IFS=$'\n\t'
set -Eeo pipefail
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Variables
#-------------------------------------------------------------------------------------------------------------------------------------------------#
AUTOMATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_PARENT_DIR="$(basename "$(dirname "$AUTOMATION_DIR")")"
BIN_DIR="$AUTOMATION_DIR/bin"
ENV_DIR="$AUTOMATION_DIR/env"
MODULES_DIR="$AUTOMATION_DIR/modules"
TEMPLATES_DIR="$AUTOMATION_DIR/templates"
OUTPUTS_DIR="$AUTOMATION_DIR/outputs"
CORE_ISSUE=0
# DEBUG_MODE=1                           # debug mode (1|0); if 1, reload_env() between steps

LOG_ID="v0.0.0.4"
LOG_FILE="$OUTPUTS_DIR/$(basename "${0}" .sh).log"
#-------------------------------------------------------------------------------------------------------------------------------------------------#
export AUTOMATION_DIR BIN_DIR ENV_DIR MODULES_DIR TEMPLATES_DIR OUTPUTS_DIR
export DEBUG_MODE
export LOG_ID LOG_FILE
#-------------------------------------------------------------------------------------------------------------------------------------------------#
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# --- core logging helpers
#-------------------------------------------------------------------------------------------------------------------------------------------------#
fallback_log() {
  local level="$1"; shift
  local log_file
  log_file="$(basename "${0}" .sh).log"

  local timestamp
  timestamp="$(date +"%Y-%m-%dT%H:%M:%S")"

  # If called via a log_* wrapper, hop two frames up; otherwise one.
  local depth=1
  case "${FUNCNAME[1]}" in
    log_info|log_debug|log_warn|log_error|log_notice|log_trace|log_fatal|log)
      depth=2
      ;;
  esac

  # File is at BASH_SOURCE[depth]; the corresponding call line is BASH_LINENO[depth-1]
  local file line
  file="${BASH_SOURCE[$depth]##*/}"
  line="${BASH_LINENO[$((depth-1))]}"
  case ${FUNCNAME[1]} in
    log_trace) 
      printf "%s %s\n" \
        "$level" "$*" \
        | tee -a "${OUTPUTS_DIR:-outputs}/$log_file" >&2;;
    log) 
      printf "%s %s\n" \
        "$line" "$*" \
        | tee -a "${OUTPUTS_DIR:-outputs}/$log_file" >&2;;
    
    *) file="${file:-<unknown>}"; line="${line:-0}" 
      printf "%-20s %-8s (%-20s:%-4s) %s\n" \
        "$timestamp" "$level" "$file" "$line" "$*" \
        | tee -a "${OUTPUTS_DIR:-outputs}/$log_file" >&2;;
    
  esac

}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
log()        {  local msg="$*";  fallback_log "[TRACE]"  "$msg";  }
log_info()   {  local msg="$*";  fallback_log "[INFO]"   "$msg";  }
log_debug()  {  local msg="$*";  fallback_log "[DEBUG]"  "$msg";  }
log_warn()   {  local msg="$*";  fallback_log "[WARN]"   "$msg";  }
log_error()  {  local msg="$*";  fallback_log "[ERROR]"  "$msg";  }
log_notice() {  local msg="$*";  fallback_log "[NOTICE]" "$msg";  }
log_trace()  {  local msg="$*";  fallback_log "[TRACE]"  "$msg";  }
log_fatal()  {  
  local msg="$*";  
  fallback_log "[FATAL] " "Exiting due to '$msg' fatal error(s); see prior log entries"
  log "#############################################################################################################"
  exit 1; 
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Core Functions
#-------------------------------------------------------------------------------------------------------------------------------------------------#
require_env() {
  local name="$1"
  local var="$*"
  log_info "[require_env:'${name:-<unset>}']"
  if [[ -z "${!var:-}" ]]; then
    log_error "[require_env(): variable not set] value='${var:-<unset>}'"
  return 10
  else
    log_debug "'$var=${!var}'"
    log_notice "[require_env():variable is set]→ '${!var:-<unset>}'"
  return 0
  fi
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
require_dir() {
  local rel
  local var_name="$*"
  local dir_path="${!var_name}"  # indirect expansion → value of that var

  log_info "[require_dir(): '$var_name']"
  log_debug "'${var_name:-<unset>}'='${dir_path:-<unset>}'"

  # if [[ "$dir_path" == "$PWD"* ]]; then
  #   rel="${dir_path#"$PWD"/}"   # strip $PWD prefix if inside current dir
  # else                                                       
  #   rel="$(basename "$dir_path")"
  # fi

  if [[ ! -d "$dir_path" ]]; then
    log_error "[require_dir(): '$var_name' is not a valid directory] value='$dir_path'"
    return 11
    else
    log_notice "[require_dir(): Directory exists]:→ '$dir_path'"
  fi
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
source_or_die() {
  local f="$1"
  local rel
  local err=0

  # Figure out relative path (without realpath)
  if [[ -n "$AUTOMATION_DIR" ]]; then
    rel="${f#"$AUTOMATION_DIR"/}"
  fi

  rel="${rel:-$(basename "$f")}"
  log_info "[source_or_die(): '$rel']"

  if [[ ! -f "$f" ]]; then
    log_error "source_or_die(): CORE File not found: '$rel'"
    err=1
  fi

  # shellcheck disable=SC1090
  if source "$f"; then
    log_notice "[source_or_die(): sourced file: '$rel']"
    return 0
  else
    err=1
  fi

  if [[ $err -eq 1 ]]; then
    log_error "[FATAL] Failed to source CORE file: '$rel'"
    return 1
  fi
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Execution
#-------------------------------------------------------------------------------------------------------------------------------------------------#

# make sure outputs dir exists
mkdir -p "$OUTPUTS_DIR"
# clear log file
: > "$LOG_FILE"
echo "" >> "$LOG_FILE"
# trap errors to provide context
# shellcheck disable=SC2154
trap '{
  local rc=$?
  local cmd=$BASH_COMMAND
  local line=$LINENO
  local file="${BASH_SOURCE[1]##*/}"
  fallback_log "[ERROR]" "Command \"$cmd\" failed with exit code $rc at ${file}:${line}"
}' ERR
log_info "[log Init: Iteration=$LOG_ID]"
log "################################################### START ###################################################"
log "#-----------------------------------------------------------------------------------------------------------#"
log "# required dependency check --------------------------------------------------------------------------------#"
# check for required dependencies
for cmd in git rsync aws terraform argocd kubectl helm jq envsubst; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    { log_error "Missing dependency: $cmd"; ((CORE_ISSUE+=1)); }
  else
    log_info "[INFO] Found dependency: $cmd"
  fi
done
#shellcheck disable=SC2129
log "# required dependency check complete ---------------------------------------------------------------------- #"
log "#-----------------------------------------------------------------------------------------------------------#"
log "# directory checks ---------------------------------------------------------------------------------------- #"
for directory in AUTOMATION_DIR \
                 BIN_DIR \
                 ENV_DIR \
                 MODULES_DIR \
                 TEMPLATES_DIR \
                 OUTPUTS_DIR; do
  if ! require_env "$directory"; then ((CORE_ISSUE+=1)); continue; fi
  log "#-----------------------------------------------------------------------------------------------------------#"
  if ! require_dir "$directory"; then ((CORE_ISSUE+=1)); fi
  if [[ "$directory" != "OUTPUTS_DIR" ]]; then log "#-----------------------------------------------------------------------------------------------------------#"; fi

done

log "# directory checks complete ------------------------------------------------------------------------------- #"
log "#-----------------------------------------------------------------------------------------------------------#"
log "# preload bin files --------------------------------------------------------------------------------------- #"

for core_file in "$AUTOMATION_DIR/customize.env" \
                 "$BIN_DIR/settings.sh" \
                 "$BIN_DIR/functions.sh" ; do
  if ! source_or_die "$core_file"; then CORE_ISSUE=$((CORE_ISSUE+1)); fi
  if [[ "$core_file" != "$BIN_DIR/functions.sh" ]]; then log "#-----------------------------------------------------------------------------------------------------------#"; fi
done

log "# preload bin files complete ------------------------------------------------------------------------------ #"
log "#-----------------------------------------------------------------------------------------------------------#"
log "# core environment check ---------------------------------------------------------------------------------- #"
log_info "Expected LOCAL_WORKING_DIR: '$LOCAL_WORKING_DIR'"
if [[ "$AUTOMATION_PARENT_DIR" != "${LOCAL_WORKING_DIR:-eks-cluster-mgmt}" ]]; then ((CORE_ISSUE+=1))
  log_warn "This script is not being run from the 'LOCAL_WORKING_DIR': '$LOCAL_WORKING_DIR' directory."
fi
log_info "Actual LOCAL_WORKING_DIR: '$AUTOMATION_PARENT_DIR'"

if [[ "$AUTOMATION_PARENT_DIR" != "$LOCAL_WORKING_DIR" ]]; then
  log_warn "It is currently running from '$AUTOMATION_PARENT_DIR' directory."
  log "Please relocate the '$(basename "$AUTOMATION_DIR")' folder to '$LOCAL_WORKING_DIR' or set the LOCAL_WORKING_DIR variable in customize.env."
else
  log_notice "This script is being run from: '$AUTOMATION_DIR'"
fi
if ((CORE_ISSUE > 0)); then
  log_fatal "$CORE_ISSUE"
fi
log "# core environment check complete ------------------------------------------------------------------------- #"
log "#-----------------------------------------------------------------------------------------------------------#"
log "# main ---------------------------------------------------------------------------------------------------- #"
echo "" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
log "#############################################################################################################"

main || log_fatal "main() failed (rc=$?)"

log "#############################################################################################################"
echo "" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
log "# main complete ------------------------------------------------------------------------------------------- #"
log "#-----------------------------------------------------------------------------------------------------------#"
log "#################################################### END ####################################################"
#-------------------------------------------------------------------------------------------------------------------------------------------------#
###################################################################################################################################################
# End of script
###################################################################################################################################################

