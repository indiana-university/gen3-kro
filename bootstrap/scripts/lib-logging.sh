#!/usr/bin/env bash
# scripts/lib-logging.sh
# Shared logging library for all scripts
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib-logging.sh"
#   log_info "This is an info message"
#   log_error "This is an error message"

# Log file location (can be overridden by caller)
LOG_FILE="${LOG_FILE:-}"

# ANSI color codes
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'

# Log function - internal use
log() {
  local level="$1"; shift
  local color="$1"; shift
  local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  local message="[${timestamp}] [${level}] $*"
  
  # Colorized output to stderr
  if [[ -t 2 ]]; then
    echo -e "${color}${message}${COLOR_RESET}" >&2
  else
    echo "$message" >&2
  fi
  
  # Also log to file if LOG_FILE is set
  if [[ -n "$LOG_FILE" ]]; then
    echo "$message" >> "$LOG_FILE"
  fi
}

# Public logging functions
log_info() {
  log "INFO " "$COLOR_BLUE" "$@"
}

log_success() {
  log "SUCCESS" "$COLOR_GREEN" "$@"
}

log_warn() {
  log "WARN " "$COLOR_YELLOW" "$@"
}

log_error() {
  log "ERROR" "$COLOR_RED" "$@"
}

log_notice() {
  log "NOTE " "$COLOR_CYAN" "$@"
}

log_debug() {
  if [[ "${VERBOSE:-0}" = "1" ]] || [[ "${DEBUG:-0}" = "1" ]]; then
    log "DEBUG" "$COLOR_RESET" "$@"
  fi
}

# Error handler - call with trap 'error_handler $LINENO' ERR
error_handler() {
  local line_number="$1"
  log_error "Script failed at line ${line_number}"
  log_error "Last command: ${BASH_COMMAND}"
  exit 1
}

# Export functions for use in subshells
export -f log log_info log_success log_warn log_error log_notice log_debug error_handler
