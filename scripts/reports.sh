#!/usr/bin/env bash
###############################################################################
# Terragrunt State Reports Generator
# Configurable reporting system driven by log-config.yaml
#
# Usage: reports.sh [LOG_DIR]
#   LOG_DIR: Directory containing terragrunt.log (optional)
#            If not provided, uses latest dev-* directory from logs_dir
###############################################################################

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CONFIG_FILE="${REPO_ROOT}/log-config.yaml"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

# Check if reports are enabled globally
if ! grep -q "^enabled: *true" "$CONFIG_FILE" 2>/dev/null; then
  echo "Reports are disabled in log-config.yaml"
  exit 0
fi

# Get timezone from config
REPORT_TZ=$(grep "^timezone:" "$CONFIG_FILE" | sed -E 's/^timezone: *"?([^"# ]+)"?.*/\1/' || echo "America/Indiana/Indianapolis")

# Get logs directory from config
LOGS_BASE=$(grep "^logs_dir:" "$CONFIG_FILE" | sed -E 's/^logs_dir: *"?([^"# ]+)"?.*/\1/' || echo "outputs/logs")
LOGS_DIR="${REPO_ROOT}/${LOGS_BASE}"

# Determine LOG_DIR from argument or find latest
if [ -n "${1:-}" ]; then
  LOG_DIR="$1"
  [[ ! "$LOG_DIR" =~ ^/ ]] && LOG_DIR="${REPO_ROOT}/${LOG_DIR}"
else
  LATEST_DIR=$(find "$LOGS_DIR" -maxdepth 1 -type d -name "dev-*" 2>/dev/null | sort -r | head -1)
  if [ -z "$LATEST_DIR" ]; then
    echo "ERROR: No log directory found in ${LOGS_DIR} and no LOG_DIR provided" >&2
    exit 1
  fi
  LOG_DIR="$LATEST_DIR"
fi

REPORT_DIR="$LOG_DIR"
SOURCE_LOG="${LOG_DIR}/terragrunt.log"

echo "==================================================================="
echo "Terragrunt State Reports Generator"
echo "==================================================================="
echo "Report directory: ${REPORT_DIR}"
echo "Configuration: ${CONFIG_FILE}"
echo ""

###############################################################################
# Helper Functions
###############################################################################

# Check if a specific report is enabled
is_enabled() {
  local section="$1"
  local report="$2"

  grep -A 500 "^  ${section}:" "$CONFIG_FILE" | \
    grep -A 1 "^    - ${report}:" | \
    grep -q "enabled: *true" 2>/dev/null
}

# Get subfolder for a report
get_subfolder() {
  local section="$1"
  local report="$2"

  grep -A 500 "^  ${section}:" "$CONFIG_FILE" | \
    grep -A 2 "^    - ${report}:" | \
    grep "subfolder:" | \
    sed -E 's/^.*subfolder: *"?([^"# ]+)"?.*/\1/' | head -1
}

# Extract resources from terragrunt log
extract_resources() {
  local log_file="$1"
  local action="$2"

  case "$action" in
    created)
      grep -E '# [^ ]+ (will be|has been) created' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) (will be|has been) created.*/\1/' | sort -u || true
      ;;
    changed)
      grep -E '# [^ ]+ (will be|has been) (updated|changed|modified)' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) (will be|has been) (updated|changed|modified).*/\1/' | sort -u || true
      ;;
    destroyed)
      grep -E '# [^ ]+ (will be|has been) destroyed' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) (will be|has been) destroyed.*/\1/' | sort -u || true
      ;;
    already-exists)
      # For "already exists", extract resources that were refreshed/read
      # 1. Managed resources that were refreshed (already exist)
      grep "Refreshing state" "$log_file" 2>/dev/null | \
        grep -oE "(module\.[^:]+|aws_[^:]+|kubernetes_[^:]+|helm_[^:]+|local_[^:]+):" | \
        sed 's/:$//' | \
        sort -u || true
      ;;
    applied-created)
      grep -E '# [^ ]+ has been created' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) has been created.*/\1/' | sort -u || true
      ;;
    applied-changed)
      grep -E '# [^ ]+ has been (updated|changed|modified)' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) has been (updated|changed|modified).*/\1/' | sort -u || true
      ;;
    applied-destroyed)
      grep -E '# [^ ]+ has been destroyed' "$log_file" 2>/dev/null | \
        sed -E 's/\x1b\[[0-9;]*m//g' | \
        sed -E 's/^.*# ([^ ]+) has been destroyed.*/\1/' | sort -u || true
      ;;
  esac
}

# Extract per-unit resource breakdown
get_unit_resources() {
  local resources="$1"
  local unit_pattern="$2"

  # Match both module.* resources and direct resources (kubernetes_, helm_, etc.)
  echo "$resources" | grep -E "(^module\.(${unit_pattern})|^(${unit_pattern}))" || true
}

# Get unique resource types from resource list
get_resource_types() {
  local resources="$1"

  # Extract resource types from both module.* and direct resources
  echo "$resources" | sed -E 's/^(module\.[^.]+(\[[^]]+\])?\.)?((aws|kubernetes|helm|local|time)_[^.[\[]+).*/\3/' | \
    grep -E '^(aws_|kubernetes_|helm_|local_|time_)' | sort -u || true
}

# Count resources
count_items() {
  local items="$1"
  if [ -z "$items" ]; then
    echo "0"
  else
    echo "$items" | grep -c '.' 2>/dev/null || echo "0"
  fi
}


###############################################################################
# Main Report Generation
###############################################################################

# Verify source log exists
if [ ! -f "$SOURCE_LOG" ]; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] ERROR: Source log not found: ${SOURCE_LOG}" >&2
  exit 1
fi

echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Generating reports from: ${SOURCE_LOG}"
echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Extracting resources..."

# Extract planned resources (will be)
RES_PLAN_CREATED=$(extract_resources "$SOURCE_LOG" "created" | grep -v "has been" || true)
RES_PLAN_CHANGED=$(extract_resources "$SOURCE_LOG" "changed" | grep -v "has been" || true)
RES_PLAN_DESTROYED=$(extract_resources "$SOURCE_LOG" "destroyed" | grep -v "has been" || true)

# Extract applied resources (has been)
RES_APPLY_CREATED=$(extract_resources "$SOURCE_LOG" "applied-created")
RES_APPLY_CHANGED=$(extract_resources "$SOURCE_LOG" "applied-changed")
RES_APPLY_DESTROYED=$(extract_resources "$SOURCE_LOG" "applied-destroyed")

# Extract already existing resources
RES_ALREADY_EXISTS=$(extract_resources "$SOURCE_LOG" "already-exists")

# Combine for backwards compatibility
RES_CREATED=$(echo -e "${RES_PLAN_CREATED}\n${RES_APPLY_CREATED}" | sort -u | grep -v '^$' || true)
RES_CHANGED=$(echo -e "${RES_PLAN_CHANGED}\n${RES_APPLY_CHANGED}" | sort -u | grep -v '^$' || true)
RES_DESTROYED=$(echo -e "${RES_PLAN_DESTROYED}\n${RES_APPLY_DESTROYED}" | sort -u | grep -v '^$' || true)

# All applied resources
RES_APPLY_ALL=$(echo -e "${RES_APPLY_CREATED}\n${RES_APPLY_CHANGED}\n${RES_APPLY_DESTROYED}" | sort -u | grep -v '^$' || true)
RES_ALL=$(echo -e "${RES_CREATED}\n${RES_CHANGED}\n${RES_DESTROYED}" | sort -u | grep -v '^$' || true)

# Count items
RES_TOTAL=$(count_items "$RES_ALL")
RES_CREATED_COUNT=$(count_items "$RES_CREATED")
RES_CHANGED_COUNT=$(count_items "$RES_CHANGED")
RES_DESTROYED_COUNT=$(count_items "$RES_DESTROYED")
RES_APPLY_CREATED_COUNT=$(count_items "$RES_APPLY_CREATED")
RES_APPLY_CHANGED_COUNT=$(count_items "$RES_APPLY_CHANGED")
RES_APPLY_DESTROYED_COUNT=$(count_items "$RES_APPLY_DESTROYED")
RES_ALREADY_EXISTS_COUNT=$(count_items "$RES_ALREADY_EXISTS")

###############################################################################
# Generate List Reports
###############################################################################
if grep -q "^  lists:" "$CONFIG_FILE" 2>/dev/null; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Generating list reports..."

  declare -A REPORT_MAP=(
    ["planned-resources"]="$RES_ALL"
    ["to-be-created-resources"]="$RES_PLAN_CREATED"
    ["to-be-changed-resources"]="$RES_PLAN_CHANGED"
    ["to-be-destroyed-resources"]="$RES_PLAN_DESTROYED"
    ["applied-resources"]="$RES_APPLY_ALL"
    ["created-resources"]="$RES_APPLY_CREATED"
    ["changed-resources"]="$RES_APPLY_CHANGED"
    ["destroyed-resources"]="$RES_APPLY_DESTROYED"
    ["already-exists-resources"]="$RES_ALREADY_EXISTS"
  )

  for report_name in "${!REPORT_MAP[@]}"; do
    if is_enabled "lists" "$report_name"; then
      subfolder=$(get_subfolder "lists" "$report_name")
      dir="${REPORT_DIR}${subfolder:+/$subfolder}"
      mkdir -p "$dir"
      echo "${REPORT_MAP[$report_name]}" > "${dir}/${report_name}.txt"
    fi
  done
fi

###############################################################################
# Generate Summary Report
###############################################################################

# Define units to analyze (used by both summary and JSON reports)
# Based on terraform/catalog/units structure
# Patterns match both module.* resources and direct kubernetes/helm resources
declare -A UNITS=(
  ["vpc"]="vpc"
  ["k8s-cluster"]="eks|aks|gke"
  ["iam-config"]="cross-account-|pod-identity-|managed-identity-|workload-identity-|spoke-policy-|spoke-role-|spoke-identity-"
  ["k8s-argocd-core"]="helm_release\.argocd|kubernetes_namespace\.argocd|helm_release\.bootstrap|kubernetes_secret_v1\.cluster|local_file\.argo"
  ["k8s-controller-req"]="kubernetes_namespace_v1\.controller|kubernetes_service_account_v1\.controller|kubernetes_config_map_v1\.controller"
  ["k8s-spoke-req"]="kubernetes_namespace_v1\.spoke_infrastructure|kubernetes_config_map_v1\.spokes_charter"
)

if is_enabled "summary" "summary"; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Generating summary..."

  subfolder=$(get_subfolder "summary" "summary")
  dir="${REPORT_DIR}${subfolder:+/$subfolder}"
  mkdir -p "$dir"

  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Analyzing per-unit resource breakdown..."

  {
    echo "==============================================================================="
    echo "TERRAGRUNT EXECUTION SUMMARY"
    echo "==============================================================================="
    echo "Generated: $(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')"
    echo "Source: ${SOURCE_LOG}"
    echo ""
    echo "==============================================================================="
    echo "OVERALL STATISTICS"
    echo "==============================================================================="
    echo ""
    echo "Resource Statistics:"
    total_with_existing=$(( RES_TOTAL + RES_ALREADY_EXISTS_COUNT ))
    echo "  Total Resources (including existing): ${total_with_existing}"
    echo "  Already Existing: ${RES_ALREADY_EXISTS_COUNT}"
    echo "  Created: ${RES_CREATED_COUNT}"
    echo "  Changed: ${RES_CHANGED_COUNT}"
    echo "  Destroyed: ${RES_DESTROYED_COUNT}"
    echo ""
    echo "==============================================================================="
    echo "PER-UNIT RESOURCE BREAKDOWN"
    echo "==============================================================================="
    echo ""

    for unit_name in vpc k8s-cluster iam-config k8s-argocd-core k8s-controller-req k8s-spoke-req; do
      unit_pattern="${UNITS[$unit_name]}"

      # Get resources for this unit
      unit_created=$(get_unit_resources "$RES_CREATED" "$unit_pattern")
      unit_changed=$(get_unit_resources "$RES_CHANGED" "$unit_pattern")
      unit_destroyed=$(get_unit_resources "$RES_DESTROYED" "$unit_pattern")
      unit_existing=$(get_unit_resources "$RES_ALREADY_EXISTS" "$unit_pattern")
      unit_all=$(echo -e "${unit_created}\n${unit_changed}\n${unit_destroyed}\n${unit_existing}" | sort -u | grep -v '^$' || true)

      # Count resources
      unit_total=$(count_items "$unit_all")
      unit_created_count=$(count_items "$unit_created")
      unit_changed_count=$(count_items "$unit_changed")
      unit_destroyed_count=$(count_items "$unit_destroyed")
      unit_existing_count=$(count_items "$unit_existing")

      # Skip units with no resources
      [ "$unit_total" -eq 0 ] && continue

      echo "Unit: ${unit_name}"
      echo "  Total Resources: ${unit_total}"
      [ "$unit_existing_count" -gt 0 ] && echo "  Already Existing: ${unit_existing_count}"
      [ "$unit_created_count" -gt 0 ] && echo "  Created: ${unit_created_count}"
      [ "$unit_changed_count" -gt 0 ] && echo "  Changed: ${unit_changed_count}"
      [ "$unit_destroyed_count" -gt 0 ] && echo "  Destroyed: ${unit_destroyed_count}"
      echo ""

      # List unique resource types for created resources
      if [ "$unit_created_count" -gt 0 ]; then
        echo "  Resource Types (Created):"
        types=$(get_resource_types "$unit_created")
        if [ -n "$types" ]; then
          while IFS= read -r type; do
            [ -z "$type" ] && continue
            # Count both module.*.type. and direct type. resources
            type_count=$(echo "$unit_created" | grep -cE "(^|\\.)${type}\\." 2>/dev/null || echo "0")
            echo "    - ${type} (${type_count})"
          done <<< "$types"
        fi
        echo ""
      fi
    done

    echo "==============================================================================="

  } > "${dir}/summary.txt"
fi

###############################################################################
# Generate Resources JSON Report
###############################################################################
if is_enabled "summary" "resources-json"; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Generating resources JSON..."

  subfolder=$(get_subfolder "summary" "resources-json")
  dir="${REPORT_DIR}${subfolder:+/$subfolder}"
  mkdir -p "$dir"

  {
    echo "{"
    echo "  \"type\": \"resources\","
    total_count=$(( RES_CREATED_COUNT + RES_CHANGED_COUNT + RES_DESTROYED_COUNT ))
    echo "  \"count\": ${total_count},"
    echo "  \"items\": ["

    first_item=true

    # Add created resources
    if [ -n "$RES_CREATED" ]; then
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$first_item" = false ]; then echo ","; fi
        first_item=false
        item_escaped=$(echo "$item" | sed 's/"/\\"/g')
        echo -n "    {\"path\": \"${item_escaped}\", \"action\": \"created\"}"
      done <<< "$RES_CREATED"
    fi

    # Add changed resources
    if [ -n "$RES_CHANGED" ]; then
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$first_item" = false ]; then echo ","; fi
        first_item=false
        item_escaped=$(echo "$item" | sed 's/"/\\"/g')
        echo -n "    {\"path\": \"${item_escaped}\", \"action\": \"changed\"}"
      done <<< "$RES_CHANGED"
    fi

    # Add destroyed resources
    if [ -n "$RES_DESTROYED" ]; then
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$first_item" = false ]; then echo ","; fi
        first_item=false
        item_escaped=$(echo "$item" | sed 's/"/\\"/g')
        echo -n "    {\"path\": \"${item_escaped}\", \"action\": \"destroyed\"}"
      done <<< "$RES_DESTROYED"
    fi

    echo ""
    echo "  ]"
    echo "}"
  } > "${dir}/resources.json"
fi

###############################################################################
# Generate Error Report
###############################################################################
if is_enabled "summary" "errors"; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Extracting errors..."

  subfolder=$(get_subfolder "summary" "errors")
  dir="${REPORT_DIR}${subfolder:+/$subfolder}"
  mkdir -p "$dir"

  grep -i 'error\|failed\|fatal' "$SOURCE_LOG" 2>/dev/null | \
    grep -v "0 error" > "${dir}/errors.txt" || echo "No errors found" > "${dir}/errors.txt"
fi

###############################################################################
# Generate terragrunt.json
###############################################################################
if is_enabled "logs" "terragrunt"; then
  echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Generating terragrunt.json..."

  {
    echo "{"
    echo "  \"execution\": {"
    echo "    \"timestamp\": \"$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')\","
    echo "    \"log_file\": \"${SOURCE_LOG}\""
    echo "  },"
    echo "  \"summary\": {"
    echo "    \"resources\": {"
    echo "      \"total\": ${RES_TOTAL},"
    echo "      \"created\": ${RES_CREATED_COUNT},"
    echo "      \"changed\": ${RES_CHANGED_COUNT},"
    echo "      \"destroyed\": ${RES_DESTROYED_COUNT}"
    echo "    }"
    echo "  },"
    echo "  \"units\": ["

    first_unit=true
    for unit_name in vpc k8s-cluster iam-config k8s-argocd-core k8s-controller-req k8s-spoke-req; do
      unit_pattern="${UNITS[$unit_name]}"

      # Get resources for this unit
      unit_created=$(get_unit_resources "$RES_CREATED" "$unit_pattern")
      unit_changed=$(get_unit_resources "$RES_CHANGED" "$unit_pattern")
      unit_destroyed=$(get_unit_resources "$RES_DESTROYED" "$unit_pattern")
      unit_all=$(echo -e "${unit_created}\n${unit_changed}\n${unit_destroyed}" | sort -u | grep -v '^$' || true)

      # Count resources
      unit_total=$(count_items "$unit_all")
      unit_created_count=$(count_items "$unit_created")
      unit_changed_count=$(count_items "$unit_changed")
      unit_destroyed_count=$(count_items "$unit_destroyed")

      # Skip units with no resources
      [ "$unit_total" -eq 0 ] && continue

      if [ "$first_unit" = false ]; then
        echo ","
      fi
      first_unit=false

      echo "    {"
      echo "      \"name\": \"${unit_name}\","
      echo "      \"total_resources\": ${unit_total},"
      echo "      \"created\": ${unit_created_count},"
      echo "      \"changed\": ${unit_changed_count},"
      echo "      \"destroyed\": ${unit_destroyed_count},"

      # Get resource types
      types=$(get_resource_types "$unit_created")
      echo "      \"resource_types\": ["
      if [ -n "$types" ]; then
        first_type=true
        while IFS= read -r type; do
          [ -z "$type" ] && continue
          # Count both module.*.type. and direct type. resources
          type_count=$(echo "$unit_created" | grep -cE "(^|\\.)${type}\\." 2>/dev/null || echo "0")
          if [ "$first_type" = false ]; then
            echo ","
          fi
          first_type=false
          echo -n "        {\"type\": \"${type}\", \"count\": ${type_count}}"
        done <<< "$types"
        echo ""
      fi
      echo "      ]"
      echo -n "    }"
    done

    echo ""
    echo "  ]"
    echo "}"
  } > "${REPORT_DIR}/terragrunt.json"
fi

echo "[$(TZ="${REPORT_TZ}" date +'%Y-%m-%d %H:%M:%S %Z')] Report generation complete: ${REPORT_DIR}"
