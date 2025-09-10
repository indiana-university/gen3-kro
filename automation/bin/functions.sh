#!/usr/bin/env bash
###################################################################################################################################################
# Shared shell utilities used across the bootstrap workflow
###################################################################################################################################################
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Variables:
: "${MAIN_LOOP_TIMEOUT_SECS:=120}"   # start pipeline prompt
: "${STEP_TIMEOUT_SECS:=120}"   # per-step prompt
: "${STEP_RETRY_TIMEOUT_SECS:=120}"  # retry prompt
: "${VAL_TIMEOUT_SECS:=10}"       # validation retry prompt
: "${MAX_CYCLE_RETRIES:=2}"
: "${MAX_STEP_RETRIES:=3}"  # max retries on failure
: "${MAX_VALIDATION_RETRIES:=1}"  # max retries on validation
: "${OUTPUTS_DIR:=outputs}"
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Functions
#-------------------------------------------------------------------------------------------------------------------------------------------------#
backup_path() {
  local p="$1"
  if [[ -e "$p" ]]; then
    local ts
    local b
    ts="$(date +%Y%m%d%H%M%S)"
    b="old/$(basename "$p")-backup-$ts"
    log_info "[backup_path():source=$(basename "$p") dest=$b]"
    log_debug "file=$(basename "$p") backup=$b path=$p"
    mkdir -p "old" || { log_error "Failed to create backup directory"; return 1; }
    cp -r "$p" "$b" || { log_error "Failed to copy $p to $b"; return 1; }
    log_notice "[backup_path()] completed successfully"
  fi
}

retry_until() {
  local sleep_secs="${1:-10}"; shift
  local warn_msg="${1:-"retrying..."}"; shift
  local rc=0
  local i=1
  local max_attempts="${MAX_VALIDATION_RETRIES:-1000}"
  log_info "[retry_until(): $*()]"
  until "$@"; do
    rc=$?

    log "#-----------------------------------------------------------------------------------------------------------#"
    log_info "$* failed in attempt #${i}/${max_attempts} (rc=${rc})"
    ((i++))

    if (( i <= max_attempts )); then
    log_warn "${warn_msg} (rc=${rc}); retrying in ${sleep_secs}s..."
    log "#-----------------------------------------------------------------------------------------------------------#"
    sleep "${sleep_secs}"
    validate_and_load_debug_files
    log "#-----------------------------------------------------------------------------------------------------------#"
    else
      log_error "[retry_until():$*()] ($max_attempts) attempts reached; giving up"
      retry_code=1
      break
    fi
  done
  if (( retry_code == 1 )); then
    return 1
  fi
  log_notice "[retry_until():$*()] function succeeded in ${i} attempt(s)"
  return 0
}
_parse_ord_path() {
  local key="$1"
  if [[ "$key" =~ ^([0-9]{2})\|(.+)$ ]]; then
    _ORD="${BASH_REMATCH[1]}"
    _PATH="${BASH_REMATCH[2]}"
    return 0
  else
    _ORD="99"
    _PATH="$key"
    return 1
  fi
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
_validate_single_file() {
  local key="$1" mark="${2:-}"
  local rel dir

  _parse_ord_path "$key" || log_warn "_validate_single_file(): invalid entry '$key' (expected 'NN|/path'); loading after prefixed entries."

  rel="${_PATH#"$PWD"/}"
  [[ "$rel" == "$_PATH" ]] && rel="$(basename -- "$_PATH")"

  if [[ -n "$mark" && "$mark" != "debug" ]]; then
    log_warn "_validate_single_file(): value for '$key' is '$mark' (only '' or 'debug' supported; others ignored)"
  fi

  dir="${_PATH%/*}"
  local had_fail=0
  if [[ ! -d "$dir" ]]; then
    log_warn "_validate_single_file(): folder missing for '$key': $dir"
    had_fail=1
  fi
  if [[ ! -e "$_PATH" ]]; then
    log_warn "_validate_single_file(): file missing for '$key': $rel"
    had_fail=1
  elif [[ ! -r "$_PATH" ]]; then
    log_warn "_validate_single_file(): file unreadable for '$key': $rel"
    had_fail=1
  fi

  (( had_fail )) && return 1 || return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
_sort_keys_by_ord() {
  local line
  while IFS= read -r line; do
    _parse_ord_path "$line"
    printf '%s\t%s\n' "$_ORD" "$line"
  done | LC_ALL=C sort -s -t $'\t' -k1,1n -k2,2
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
validate_and_load_default_files() {
  log_info "[validate_and_load_default_files()=DEFAULT_FILES]"

  local type_decl had_fail=0 key
  if ! type_decl="$(declare -p DEFAULT_FILES 2>/dev/null)"; then
    log_error "validate_and_load_default_files(): DEFAULT_FILES is not defined (declare -ag DEFAULT_FILES required)"
    return 1
  fi
  if [[ "$type_decl" != "declare -a"* ]]; then
    log_error "validate_and_load_default_files(): DEFAULT_FILES must be an indexed array (declare -ag). Found: $type_decl"
    return 1
  fi

  # Validate & collect
  local tmpfile
  tmpfile="$(mktemp)" || { log_error "mktemp failed"; return 1; }
  : > "$tmpfile"

  for key in "${DEFAULT_FILES[@]}"; do
    _validate_single_file "$key" "" || had_fail=1
    echo "$key" >> "$tmpfile"
  done

  if (( had_fail )); then
    rm -f "$tmpfile"
    log_error "validate_and_load_default_files(): validation failed for one or more entries."
    return 12
  fi

  # Build sorted keys
  mapfile -t _DEFAULT_SORTED_KEYS < <(cat "$tmpfile" | _sort_keys_by_ord | cut -f2-)
  rm -f "$tmpfile"

  # Load (once)
  local path
  for key in "${_DEFAULT_SORTED_KEYS[@]}"; do
    _parse_ord_path "$key"
    path="$_PATH"
    # shellcheck source=/dev/null
    if source "$path"; then
      log_debug "default: loaded $path"
    else
      log_error "default: failed to load $path"
      return 13
    fi
  done

  log_notice "[SUCCESS] default files validated and loaded."
  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
validate_and_load_debug_files() {
  log_info "[validate_and_load_debug_files()=DEBUG_MODE_FILES]"
  local type_decl had_fail=0 k i
  if [[ -z $DEBUG_MODE_FILES ]]; then
    log_info "[DEBUG_MODE_FILES is empty; skipping]"
    return 0
  fi
  if ! type_decl="$(declare -p DEBUG_MODE_FILES 2>/dev/null)"; then
    log_error "DEBUG_MODE_FILES not defined (declare -ag required)"
    return 14
  fi
  if [[ "$type_decl" != "declare -a"* ]]; then
    log_error "DEBUG_MODE_FILES must be an indexed array. Found: $type_decl"
    return 15
  fi
  i=0
  for i in "${!DEBUG_MODE_FILES[@]}"; do
    log_debug "'DEBUG_MODE_FILES[$i]'=${DEBUG_MODE_FILES[$i]}"
  done

  mapfile -t _DEBUG_SORTED_KEYS < <(
    printf '%s\n' "${DEBUG_MODE_FILES[@]}" | _sort_keys_by_ord | cut -f2-
  )

  local path
  local i=0
  for k in "${_DEBUG_SORTED_KEYS[@]}"; do
    _parse_ord_path "$k"
    path="$_PATH"
    log_debug "'_DEBUG_SORTED_KEYS[${i}]'=$path"
    ((i++))
    # shellcheck source=/dev/null
    if source "$path"; then
      continue
    else
      log_error "debug: failed to load $path"
      ((had_fail++))
    fi
  done

  if (( had_fail!=0 )); then
    log_error "[validate_and_load_debug_files()=FAILED]:→ $had_fail files failed"
    return 15
  fi

  log_notice "[validate_and_load_debug_files()=PASSED]:→ debug files validated and loaded."
  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
validate_steps_exec_mode() {
  log_info "[validate_steps_exec_mode:STEPS_EXEC_MODE]"
  local type_decl
  if ! type_decl="$(declare -p STEPS_EXEC_MODE 2>/dev/null)"; then
    log_error "STEPS_EXEC_MODE not defined (declare -A -g required)."
    return 16
  fi
  if [[ "$type_decl" != "declare -A"* ]]; then
    log_error "STEPS_EXEC_MODE must be an associative array. Found: $type_decl"
    return 17
  fi
  if ((${#STEPS_EXEC_MODE[@]} == 0)); then
    log_error "STEPS_EXEC_MODE is empty."
    return 18
  fi

  # Build ordered script_list from KEYS of STEPS_EXEC_MODE
  mapfile -t script_list < <(
  printf '%s\n' "${!STEPS_EXEC_MODE[@]}" | LC_ALL=C sort -t'-' -k1,1n
  )
  log_info "Scripts to run (in order): ${#script_list[@]}"

  local script
  local issue=0
  local i=0
  for script in "${script_list[@]}"; do
    if [[ ! -f "$MODULES_DIR/$script" ]]; then
      log_error "module script not found: ${script:-<unset>}"
      ((issue++))
    fi
    if [[ $issue = 0 ]]; then
      local mode="${STEPS_EXEC_MODE[$script]:-${EXEC_MODE_DEFAULT:-ask}}"
      if [[ "$mode" != "ask" && "$mode" != "auto" ]]; then
        log_error "validate_steps_exec_mode(): invalid mode for '$script': '$mode' (must be 'ask' or 'auto')"
      fi
      log_debug "'script_list[$i]'='$script'; [mode=$mode]"
    fi
    ((i++))
  done
  if (( issue == 1 )); then
    log_error "validate_steps_exec_mode(): failed with $issue issue(s); see prior log entries"
    return 19
  fi
  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
load_modules() {
  local debug_mode="${1:-1}"
  local script="${2:-}"
  local path rc
  log_info "[load_modules()=${script:-<unset>}]"
  if [[ $step_retry_count == 0 ]]; then
    RETRY_ID="attempt 1"
  else
    RETRY_ID=" retry: $step_retry_count/$max_step_retries"
  fi
  log "#--------------------------------------------- $RETRY_ID ---------------------------------------------------------#"
  path="$MODULES_DIR/$script"
  ERR_FILE="${OUTPUTS_DIR}/${script//\//_}.stderr.log"
  # Per-module env reload (debug)
  if (( debug_mode == 1 )); then
    if ! validate_and_load_debug_files; then
      log_error "load_modules(): validate_and_load_debug_files failed (debug mode)."
      LAST_MODULE_RC=3
      return 20
    fi
  fi

  CURR_LOG_FILE="$LOG_FILE"
  LOG_FILE=$ERR_FILE
  # shellcheck disable=SC1090
  if source "$path" 2> "$ERR_FILE"; then
    LOG_FILE="$CURR_LOG_FILE"
    log_info "[load_modules()=script:$script] completed successfully."
    log "#############################################################################################################"
    LAST_MODULE_RC=0
    rm -f "$ERR_FILE"
    return 0
  else
    rc=$?
    LAST_MODULE_RC=$rc
    LOG_FILE="$CURR_LOG_FILE"
    log_error "[load_modules()=script:$script] failed: (rc=$rc)"
    log "#############################################################################################################"
    if [[ -s "$ERR_FILE" ]]; then
      if [[ $step_retry_count == "$max_step_retries" ]]; then
        log "'Error output from $script:'"
        log_trace "#-----------------------------------------------------------------------------------------------------------#"
        while IFS= read -r line; do
          log_trace "$line"
        done < "$ERR_FILE"
      fi
    fi
    rm -f "$ERR_FILE"
    return 21
  fi
}


#-------------------------------------------------------------------------------------------------------------------------------------------------#
run_module_with_retries() {
  local debug_mode="${1:-1}"
  local script="${2:-}"
  local max_step_retries="${MAX_STEP_RETRIES:-3}"
  local retry_timeout="${STEP_RETRY_TIMEOUT_SECS:-120}"
  local step_retry_count=0
  until load_modules "$debug_mode" "$script"; do
    log_trace "$(date +'%Y-%m-%d %H:%M:%S')  [ERROR]  (functions.sh        :320 ) ✖ retry:$step_retry_count] $script module failed with error code: (rc=${LAST_MODULE_RC:-1})."
    log "#############################################################################################################"

    if (( step_retry_count >= max_step_retries )); then
      log_error "Reached maximum retries ($max_step_retries). Quitting pipeline."
      return 23
    fi

    local choice=""
    if read -r -t "$retry_timeout" \
      -p $'[r]etry / [s]kip / [q]uit pipeline (Waiting for '"$retry_timeout"' seconds...): ' choice
    then
      case "${choice,,}" in
        r|retry)
          ((step_retry_count++))
          log_info "Retrying: step $step_retry_count/$max_step_retries"
          # loop continues
          ;;
        s|skip)
          return 25
          ;;
        q|quit)
          return 26
          ;;
        *)
          log "Please answer r, s or q."
          # re-prompt on next failure loop
          ;;
      esac
    else
      ((step_retry_count++))
      log_warn "No input after ${retry_timeout}s — retrying ($step_retry_count/$max_step_retries)..."
    fi
  done

  return 0
}

#-------------------------------------------------------------------------------------------------------------------------------------------------#
primer() {
  local retry_code=0
  log_info "[ENTER:PRIMER]"
  log "#-----------------------------------------------------------------------------------------------------------#"

  # Load defaults once (combined validate+load), retry until success
  if ! retry_until "${VAL_TIMEOUT_SECS:-120}" \
    "[validate_and_load_default_files(): failed]" \
    validate_and_load_default_files
  then return 1; fi

  log "#-----------------------------------------------------------------------------------------------------------#"

  # Build/validate the script_list from STEPS_EXEC_MODE, retry until success
  if ! retry_until "${VAL_TIMEOUT_SECS:-10}" \
    "[validate_steps_exec_mode(): failed]" \
    validate_steps_exec_mode
  then return 1; fi

  log "#-----------------------------------------------------------------------------------------------------------#"
  log_notice "[SUCCESS=PRIMER]"
  log "# primer complete ----------------------------------------------------------------------------------------- #"
  log "#-----------------------------------------------------------------------------------------------------------#"
(( ++LOOP_ID ))
END_LOOP_ID=$MAX_CYCLE_RETRIES
  log "############################################ LOOP ID: $LOOP_ID/$END_LOOP_ID ###################################################"
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Main loop over scripts
main() {
  read -r -t "${MAIN_LOOP_TIMEOUT_SECS:-120}" \
    -p $'   Start pipeline? [y]es / [q]uit pipeline (Waiting for '"${MAIN_LOOP_TIMEOUT_SECS:-120}"' seconds...): ' choice

  if [[ -z "$choice" || "${choice,,}" == "y" || "${choice,,}" == "yes" ]]; then

  log "# primer -------------------------------------------------------------------------------------------------- #"
  if ! primer; then return 1; fi

    local rc 
    local step=0
    local cycle_retry_count=0
    local max_cycle_retries=$MAX_CYCLE_RETRIES
    local total="${#script_list[@]}"
    local debug_mode="${DEBUG_MODE:-1}"  # refresh in case it changed

    while :; do
      
      # Completed a full pass?
      if (( step >= total )); then
        log_debug "step=$step total=$total"
        log_notice "✔ Loop complete (all $total scripts processed)."
        log "#############################################################################################################"
        
        if (( cycle_retry_count >= max_cycle_retries )); then
          log_info "Reached maximum pipeline cycles ($max_cycle_retries). Exiting normally."
          return 0
        fi

        ((++cycle_retry_count))   
        log "#-----------------------------------------------------------------------------------------------------------#"
        if read -r -t "${MAIN_LOOP_TIMEOUT_SECS:-120}" \
          -p $'   Restart pipeline? [y]es / [q]uit pipeline (Waiting for '"${MAIN_LOOP_TIMEOUT_SECS:-120}"' seconds...): ' choice
          then
          case "${choice,,}" in
            q|quit)
              log_info "Exiting pipeline as requested."
              return 0
              ;;
            y|yes)

              log_notice "[RESTART=MAIN]: Attempt #${cycle_retry_count}/${max_cycle_retries}"
              log "#-----------------------------------------------------------------------------------------------------------#"
              log "#############################################################################################################"
              log "#-----------------------------------------------------------------------------------------------------------#"
              
              if (( debug_mode == 1 )); then
                if ! retry_until "${VAL_TIMEOUT_SECS:-10}" \
                  "[validate_and_load_debug_files(): failed]" \
                  validate_and_load_debug_files
                then return 1; fi
                log "#-----------------------------------------------------------------------------------------------------------#"
              fi

              log "# primer -------------------------------------------------------------------------------------------------- #"
              if ! primer; then return 1; fi
              ;;
          esac
        else
          log_info "No input after ${STEP_TIMEOUT_SECS:-120}s — restarting pipeline."
        fi
        step=0
        total="${#script_list[@]}"  # refresh in case it changed
      fi
      # Pull the next script and its mode (EXEC_MODE is optional; defaults to ask)
      local script="${script_list[$step]}"
      local mode="${STEPS_EXEC_MODE[$script]:-${EXEC_MODE_DEFAULT:-ask}}"

      printf "→ (%d/%d) %s  [mode: %s]\n" "$((step + 1))" "$total" "$script" "$mode"
      log_debug "step=$step script=$script mode=$mode DEBUG_MODE=${debug_mode}"
      # Per-module prompt/flow
      case "$mode" in
        ask)
          if (( ${debug_mode:-1} )); then
            local choice=""
            if read -r -t "${STEP_TIMEOUT_SECS:-120}" \
              -p $'   Run this step? [y]es / [s]kip / [e]nd pipeline (Waiting for '"${STEP_TIMEOUT_SECS:-120}"' seconds...): ' choice
            then
              case "${choice,,}" in
                y|yes) : ;;                                   # proceed
                s|skip) ((++step)); continue ;;               # skip to next
                e|end) step=$total;       continue ;;        # end pipeline
                *) echo "   Please answer y, s, or e."; continue ;;
              esac
            else
              echo "   No input after ${STEP_TIMEOUT_SECS:-120}s — proceeding with this step."
            fi
          fi
          ;;
        auto)
          echo "   Running step automatically (no delay)..."
          ;;
        *)
          log_warn "Unknown EXEC_MODE '$mode' for $script"
          if (( ${debug_mode:-1} )); then
            local choice=""
            if read -r -t "${STEP_TIMEOUT_SECS:-120}" \
              -p $'   Run this step? [y]es / [s]kip / [e]xit pipeline (Waiting for '"${STEP_TIMEOUT_SECS:-120}"' seconds...): ' choice
            then
              case "${choice,,}" in
                y|yes) : ;;                                   # proceed
                s|skip) ((++step)); continue ;;               # skip
                e|exit) step=$total;       continue ;;        # end
                *) echo "   Please answer y, s, or e."; continue ;;
              esac
            else
              echo "   No input after ${STEP_TIMEOUT_SECS:-120}s — proceeding with this step."
            fi
          fi
          ;;
      esac

      if ! run_module_with_retries "$debug_mode" "$script"; then
        log_error "main(): run_module_with_retries() failed(rc=$LAST_MODULE_RC)"
        return 1
      fi
      ((++step))

    done
  elif [[ "${choice,,}" == "q" || "${choice,,}" == "quit" ]]; then
    log_notice "Pipeline aborted by user"

  else
    log_warn "Invalid choice: $choice (expected y/yes or q/quit)"
    return 1
  fi
}
#-------------------------------------------------------------------------------------------------------------------------------------------------#
# Module Functions
#-------------------------------------------------------------------------------------------------------------------------------------------------#
run() {
  local start end dur rc
  local cmd_str cmd_name logfile

  cmd_str=$(printf '%q ' "$@")   # full command for logging
  cmd_name=$(basename "$1")      # just the command (e.g., terraform, docker, ls)
  logfile="$OUTPUTS_DIR/${cmd_name}.log"

  log_info "[run()=argv:'$cmd_str' argc:'$#' PWD:'$PWD']"
  start=$SECONDS

  # Redirect stdout/stderr to logfile + console
  if [[ $cmd_name == "terraform" ]]; then
    "$@" 2>&1 | tee >(sed -r "s/\x1B\[[0-9;]*[mK]//g" >> "$logfile")
  else
    "$@" 2>&1 | tee -a "$logfile"
  fi
  rc=${PIPESTATUS[0]}

  end=$SECONDS; dur=$(( end - start ))

  if (( rc == 0 )); then
    log_info "[run()=Command SUCCESS $rc (duration=${dur}s): $cmd_str]"
  else
    log_error "[run()=Command FAILED $rc (duration=${dur}s): $cmd_str]"
  fi

  return "$rc"
}

###################################################################################################################################################
# End of file
###################################################################################################################################################
