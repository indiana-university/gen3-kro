#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

usage() {
  cat <<'USAGE'
Usage: bash scripts/terragrunt-stack.sh <stack> <command> [unit]

Stacks:
  operators-iam
  csoc-cluster-core
  spoke-fleet-update

Commands:
  generate  Generate Terragrunt stack units
  init      Initialize the stack or selected unit
  plan      Plan the stack or selected unit
  apply     Apply the stack or selected unit
  destroy   Destroy the stack or selected unit
  output    Show stack or selected-unit outputs
USAGE
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

STACK_NAME="$1"
COMMAND="$2"
UNIT_NAME="${3:-}"

case "$STACK_NAME" in
  operators-iam|csoc-cluster-core|spoke-fleet-update) ;;
  *)
    echo "FATAL: unknown Terragrunt stack: ${STACK_NAME}" >&2
    usage >&2
    exit 1
    ;;
esac

case "$COMMAND" in
  generate|init|plan|apply|destroy|output) ;;
  *)
    echo "FATAL: unknown Terragrunt command: ${COMMAND}" >&2
    usage >&2
    exit 1
    ;;
esac

for required_command in terragrunt jq; do
  command -v "$required_command" >/dev/null 2>&1 || {
    echo "FATAL: ${required_command} is not installed or not on PATH." >&2
    exit 1
  }
done

STACK_DIR="${REPO_ROOT}/terragrunt/live/aws/${STACK_NAME}"
[[ -f "${STACK_DIR}/terragrunt.stack.hcl" ]] || {
  echo "FATAL: Terragrunt stack not found: ${STACK_DIR}" >&2
  exit 1
}

# Each generated unit owns its Terraform metadata and backend selection.
unset TF_DATA_DIR

if [[ "$STACK_NAME" == "spoke-fleet-update" && "$UNIT_NAME" == "aws-spoke-access-iam" ]]; then
  SPOKE_ALIAS="${TG_SPOKE_ALIAS:-}"
  if [[ -z "$SPOKE_ALIAS" ]]; then
    SPOKE_ALIAS="$(jq -r '[.spokes[] | select(.enabled == true)] | if length == 1 then .[0].alias else empty end' "${REPO_ROOT}/config/shared.auto.tfvars.json")"
  fi
  [[ -n "$SPOKE_ALIAS" ]] || {
    echo "FATAL: set TG_SPOKE_ALIAS when more than one spoke is enabled." >&2
    exit 1
  }
  UNIT_NAME="aws-spoke-access-iam-${SPOKE_ALIAS}"
fi

terragrunt_clean() {
  terragrunt --no-color --log-format json --log-level info "$@"
}

generate_stack() {
  (cd "$STACK_DIR" && terragrunt_clean stack generate)
}

unit_dir() {
  printf '%s/.terragrunt-stack/%s\n' "$STACK_DIR" "$UNIT_NAME"
}

run_unit_action() {
  local generated_unit_dir
  generated_unit_dir="$(unit_dir)"
  [[ -d "$generated_unit_dir" ]] || {
    echo "FATAL: generated unit not found: ${UNIT_NAME}" >&2
    return 1
  }

  case "$COMMAND" in
    plan)
      (cd "$generated_unit_dir" && terragrunt_clean plan -input=false -out="$UNIT_PLAN_TEMP")
      ;;
    output)
      (cd "$generated_unit_dir" && terragrunt output)
      ;;
    init)
      (cd "$generated_unit_dir" && terragrunt_clean init -reconfigure -input=false)
      ;;
    apply|destroy)
      (cd "$generated_unit_dir" && terragrunt_clean "$COMMAND")
      ;;
    generate) ;;
  esac
}

run_stack_action() {
  local -a command_args=(
    stack run "$COMMAND"
    --report-file "$ACTION_REPORT"
    --report-format json
  )

  if [[ "$COMMAND" == "plan" ]]; then
    command_args+=(--out-dir "$PLAN_TEMP_DIR")
  fi

  (cd "$STACK_DIR" && terragrunt_clean "${command_args[@]}")
}

route_action_logs() {
  local default_route="$1"
  local -a route_status
  local jq_status
  local writer_status

  jq --unbuffered -Rj \
    --arg default_route "$default_route" \
    --arg stack_units_dir "${STACK_DIR}/.terragrunt-stack/" '
    . as $raw
    | (try fromjson catch null) as $record
    | if ($record | type) == "object" then
        ($record["working-dir"] // "") as $working_dir
        | (($record.level // "info") | tostring | ascii_upcase) as $level
        | (($record.msg // $raw) | tostring
            | gsub("[^\\s]*\\.terragrunt-stack/[A-Za-z0-9._-]+/\\.terragrunt-cache/[^\\s]+"; "<terragrunt-cache>")) as $message
        | if ($working_dir == "" or $working_dir == ".") then
            "\($default_route)\u0000\($level) \($message)\u0000"
          elif ($working_dir | test("^\\.terragrunt-stack/[A-Za-z0-9._-]+$")) then
            ($working_dir | split("/") | last) as $unit
            | "\($unit)\u0000\($level) \($message)\u0000"
          elif ($working_dir | startswith($stack_units_dir)) then
            ($working_dir | ltrimstr($stack_units_dir)) as $unit
            | if ($unit | test("^[A-Za-z0-9._-]+$")) then
                "\($unit)\u0000\($level) \($message)\u0000"
              else
                "core\u0000WARN rejected unsafe Terragrunt working-dir: \($working_dir)\u0000"
              end
          else
            "core\u0000WARN rejected unsafe Terragrunt working-dir: \($working_dir)\u0000"
          end
      else
        if ($raw | test("^\\s*[\\{\\[]")) then
          "core\u0000WARN rejected malformed Terragrunt JSON record: \($raw)\u0000"
        else
          "\($default_route)\u0000\($raw)\u0000"
        end
      end
  ' | while IFS= read -r -d '' route && IFS= read -r -d '' message; do
    local destination
    local line
    local warning

    if [[ "$route" == "core" ]]; then
      destination="$CORE_LOG"
      printf '%s\n' "$message" >> "$destination" || exit 1
      printf '%s\n' "$message" || exit 1
      continue
    fi

    if [[ ! "$route" =~ ^[A-Za-z0-9._-]+$ ]]; then
      warning="WARN rejected unsafe routed unit: ${route}"
      printf '%s\n' "$warning" >> "$CORE_LOG" || exit 1
      printf '%s\n' "$warning" || exit 1
      continue
    fi

    destination="${STACK_LOG_DIR}/${COMMAND}-${route}.log"
    printf '%s\n' "$message" >> "$destination" || exit 1
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '[%s] %s\n' "$route" "$line" || exit 1
    done <<< "$message"
  done

  route_status=("${PIPESTATUS[@]}")
  jq_status="${route_status[0]}"
  writer_status="${route_status[1]}"
  if [[ "$jq_status" -ne 0 ]]; then
    printf 'ERROR Terragrunt log JSON routing failed with status %s\n' "$jq_status" | tee -a "$CORE_LOG" >&2
    return "$jq_status"
  fi
  return "$writer_status"
}

run_routed() {
  local default_route="$1"
  shift
  local -a pipeline_status
  local command_status
  local router_status

  if "$@" 2>&1 | route_action_logs "$default_route"; then
    pipeline_status=("${PIPESTATUS[@]}")
  else
    pipeline_status=("${PIPESTATUS[@]}")
  fi

  command_status="${pipeline_status[0]}"
  router_status="${pipeline_status[1]}"
  if [[ "$command_status" -ne 0 ]]; then
    return "$command_status"
  fi
  return "$router_status"
}

run_logged_action() {
  local command_status=0

  if [[ -n "$UNIT_NAME" ]]; then
    run_routed core generate_stack || command_status=$?
    if [[ "$command_status" -eq 0 ]]; then
      run_routed "$UNIT_NAME" run_unit_action || command_status=$?
    fi
  else
    run_routed core run_stack_action || command_status=$?
  fi

  return "$command_status"
}

case "$COMMAND" in
  plan|init|apply|destroy)
    OUTPUT_ROOT="${REPO_ROOT}/outputs"
    source "${SCRIPT_DIR}/lib/output-paths.sh"
    STACK_LOG_DIR="${TERRAGRUNT_DIR}/${STACK_NAME}"
    CORE_LOG="${STACK_LOG_DIR}/${COMMAND}-core.log"
    ACTION_REPORT="${STACK_LOG_DIR}/${COMMAND}-report.json"
    PLAN_DIR="${STACK_LOG_DIR}/plan-files"
    PLAN_TEMP_DIR="${STACK_LOG_DIR}/.plan-files.tmp"
    UNIT_PLAN="${PLAN_DIR}/${UNIT_NAME:-all}.tfplan"
    UNIT_PLAN_TEMP="${STACK_LOG_DIR}/.${UNIT_NAME:-all}.tfplan.tmp"

    mkdir -p "$STACK_LOG_DIR"
    find "$STACK_LOG_DIR" -maxdepth 1 -type f -name "${COMMAND}-*.log" -delete
    rm -f "${STACK_LOG_DIR}/${COMMAND}.log" \
      "${STACK_LOG_DIR}/${COMMAND}-report.csv" \
      "$ACTION_REPORT" \
      "$UNIT_PLAN_TEMP"
    : > "$CORE_LOG"

    if [[ "$COMMAND" == "plan" ]]; then
      rm -rf "$PLAN_DIR" "$PLAN_TEMP_DIR"
      if [[ -n "$UNIT_NAME" ]]; then
        mkdir -p "$PLAN_DIR"
      fi
    fi

    COMMAND_STATUS=0
    run_logged_action || COMMAND_STATUS=$?

    if [[ "$COMMAND" == "plan" ]]; then
      if [[ "$COMMAND_STATUS" -eq 0 && -z "$UNIT_NAME" ]]; then
        mv "$PLAN_TEMP_DIR" "$PLAN_DIR"
      elif [[ "$COMMAND_STATUS" -eq 0 ]]; then
        mv "$UNIT_PLAN_TEMP" "$UNIT_PLAN"
      else
        rm -rf "$PLAN_TEMP_DIR"
        rm -f "$UNIT_PLAN_TEMP"
      fi
    fi
    exit "$COMMAND_STATUS"
    ;;
  generate)
    (cd "$STACK_DIR" && terragrunt stack generate)
    ;;
  output)
    if [[ -n "$UNIT_NAME" ]]; then
      (cd "$STACK_DIR" && terragrunt stack generate)
      run_unit_action
    else
      (cd "$STACK_DIR" && terragrunt stack output)
    fi
    ;;
esac
