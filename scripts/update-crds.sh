#!/bin/bash
#
# Controller Version & CRD Update Script
#
# Workflow:
# 1. Check controller catalog for list of controllers and required data
# 2. Check for latest versions (catch rate limits early, exit after all checked)
# 3. Display upgrades available and controllers with CRD changes
# 4. Prompt user to update controller catalog
# 5. Clear /tmp/download folder
# 6. Download CRDs at updated catalog version to /tmp with kustomization files
# 7. Replace subdirectories in argocd/csoc-addons/crds
#

set -euo pipefail

# ============================================================================
# Configuration and Colors
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CATALOG_FILE="${WORKSPACE_ROOT}/argocd/csoc-addons/controller-catalog.yaml"
CRD_BASE_DIR="${WORKSPACE_ROOT}/argocd/csoc-addons/crds"
OUTPUT_DIR="${WORKSPACE_ROOT}/outputs"
TEMP_DOWNLOAD_DIR="/tmp/kro-controller-downloads"

# Configurable settings
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
API_TIMEOUT="${API_TIMEOUT:-10}"
API_CONNECT_TIMEOUT="${API_CONNECT_TIMEOUT:-5}"
MAX_PARALLEL_DOWNLOADS="${MAX_PARALLEL_DOWNLOADS:-5}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VERSION_REPORT="${OUTPUT_DIR}/controller-versions-${TIMESTAMP}.log"
CRD_REPORT="${OUTPUT_DIR}/crd-updates-${TIMESTAMP}.log"
DRY_RUN=0

# Global arrays and maps
declare -a CONTROLLERS=()
declare -A CONTROLLER_NAMESPACE
declare -A CONTROLLER_REPO_URL
declare -A CONTROLLER_CURRENT_VERSION
declare -A CONTROLLER_CHART_NAME
declare -A CONTROLLER_GITHUB_REPO
declare -A CONTROLLER_GITHUB_CRD_PATH
declare -A CONTROLLER_LATEST_VERSION
declare -A CONTROLLER_NEEDS_UPGRADE
declare -A CONTROLLER_CRD_COUNT
declare -a UPDATED_CONTROLLERS=()
declare -A GITHUB_REPO_CACHE

# Statistics
TOTAL_CONTROLLERS=0
UPGRADES_AVAILABLE=0
RATE_LIMITED=0
LAST_ERROR=""
GITHUB_LATEST_VERSION_RESULT=""

mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Cleanup Function
# ============================================================================

cleanup() {
    if [[ -d "$TEMP_DOWNLOAD_DIR" ]]; then
        rm -rf "$TEMP_DOWNLOAD_DIR"
    fi
}
trap cleanup EXIT

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

# Fallback for column command (fixes #16)
safe_column() {
    if command -v column &> /dev/null; then
        column "$@"
    else
        # Simple fallback - just cat the input
        cat
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

extract_github_repo() {
    local url="$1"
    if [[ "$url" =~ github.com/([^/]+/[^/]+) ]]; then
        echo "${BASH_REMATCH[1]}" | sed 's/\.git$//'
    else
        echo ""
    fi
}

compare_versions() {
    local current="$1"
    local latest="$2"

    if [[ "$current" == "$latest" ]]; then
        echo "equal"
    elif [[ "$(printf '%s\n%s' "$current" "$latest" | sort -V | head -1)" == "$current" ]]; then
        echo "older"
    else
        echo "newer"
    fi
}

clear_temp_download() {
    log_info "Clearing temporary download directory..."
    rm -rf "$TEMP_DOWNLOAD_DIR"
    mkdir -p "$TEMP_DOWNLOAD_DIR"
}

# ============================================================================
# GitHub API Functions
# ============================================================================

check_rate_limit() {
    local check_url="https://api.github.com/rate_limit"
    local headers=()
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi

    local response=$(curl -s "${headers[@]}" "$check_url" 2>/dev/null)
    local remaining=$(echo "$response" | jq -r '.resources.core.remaining // 0' 2>/dev/null)
    local limit=$(echo "$response" | jq -r '.resources.core.limit // 60' 2>/dev/null)
    local reset=$(echo "$response" | jq -r '.resources.core.reset // 0' 2>/dev/null)

    if [[ "$remaining" -eq 0 ]]; then
        local reset_time_utc=$(TZ=UTC date -d "@$reset" "+%a %b %d %I:%M:%S %p UTC %Y" 2>/dev/null || echo "unknown")
        local reset_time_est=$(TZ=America/New_York date -d "@$reset" "+%a %b %d %I:%M:%S %p EST %Y" 2>/dev/null || echo "unknown")
        log_error "GitHub API rate limit exceeded (0/$limit requests remaining)"
        log_info "Rate limit resets at: $reset_time_est ($reset_time_utc)"
        log_info "Set GITHUB_TOKEN to increase limit to 5,000/hour"
        log_info "Get token at: https://github.com/settings/tokens"
        return 1
    elif [[ "$remaining" -lt 10 ]]; then
        log_warning "GitHub API rate limit low: $remaining/$limit requests remaining"
        if [[ -z "$GITHUB_TOKEN" ]]; then
            log_info "Consider setting GITHUB_TOKEN to increase limit to 5,000/hour"
        fi
    else
        if [[ -n "${DEBUG:-}" ]]; then
            log_info "GitHub API: $remaining/$limit requests remaining"
        fi
    fi
    return 0
}

get_github_latest_version() {
    local repo="$1"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    LAST_ERROR=""  # Clear previous error

    local headers=(-H "Accept: application/vnd.github.v3+json")
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi

    set +e
    local response=$(curl -L --max-time "$API_TIMEOUT" --connect-timeout "$API_CONNECT_TIMEOUT" -s "${headers[@]}" "$api_url" 2>&1)
    local curl_exit=$?
    set -e

    # Debug: Show first part of response
    if [[ -n "${DEBUG:-}" ]]; then
        echo "  [DEBUG] curl exit: $curl_exit" >&2
        echo "  [DEBUG] response: ${response:0:100}..." >&2
    fi

    if [[ $curl_exit -eq 28 ]]; then
        LAST_ERROR="Timeout"
        return 1
    elif [[ $curl_exit -ne 0 ]]; then
        LAST_ERROR="Network error (code: $curl_exit)"
        return 1
    fi

    if echo "$response" | grep -qi 'rate limit'; then
        RATE_LIMITED=1
        LAST_ERROR="Rate limited"
        return 1
    fi

    local message=$(echo "$response" | jq -r '.message // ""' 2>/dev/null)
    if [[ "$message" == "Not Found" ]]; then
        LAST_ERROR="Repo not found"
        return 1
    elif [[ -n "$message" && "$message" != "null" && "$message" != "" ]]; then
        LAST_ERROR="API error: $message"
        return 1
    fi

    local tag=$(echo "$response" | jq -r '.tag_name // ""' 2>/dev/null)

    if [[ -n "$tag" && "$tag" != "null" && "$tag" != "" ]]; then
        GITHUB_LATEST_VERSION_RESULT=$(echo "$tag" | sed 's/^v//')
        return 0
    fi

    LAST_ERROR="No release found"
    return 1
}

get_controller_github_repo() {
    local addon="$1"
    local repo_url="$2"
    local chart_name="$3"

    # Check cache first (fixes #11)
    if [[ -n "${GITHUB_REPO_CACHE[$addon]:-}" ]]; then
        echo "${GITHUB_REPO_CACHE[$addon]}"
        return 0
    fi

    local result=""

    # Check catalog field first
    if [[ -n "${CONTROLLER_GITHUB_REPO[$addon]:-}" ]]; then
        result="${CONTROLLER_GITHUB_REPO[$addon]}"
    # Direct GitHub URL
    elif [[ "$repo_url" =~ github\.com ]]; then
        result=$(extract_github_repo "$repo_url")
    # ACK controllers
    elif [[ "$chart_name" =~ ^(.+)-chart$ ]]; then
        result="aws-controllers-k8s/${BASH_REMATCH[1]}-controller"
    fi

    if [[ -n "$result" ]]; then
        GITHUB_REPO_CACHE["$addon"]="$result"
        echo "$result"
        return 0
    fi

    return 1
}

download_crds_from_github() {
    local github_repo="$1"
    local version="$2"
    local crd_path="$3"
    local output_dir="$4"

    local found=0
    local api_url="https://api.github.com/repos/${github_repo}/contents/${crd_path}?ref=v${version}"

    local headers=(-H "Accept: application/vnd.github.v3+json")
    if [[ -n "$GITHUB_TOKEN" ]]; then
        headers+=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi

    set +e
    local response=$(curl -L -s "${headers[@]}" "$api_url" 2>/dev/null)
    local curl_exit=$?
    set -e

    if [[ $curl_exit -ne 0 ]]; then
        return 1
    fi

    if echo "$response" | grep -qi 'rate limit'; then
        RATE_LIMITED=1
        return 1
    fi

    local message=$(echo "$response" | jq -r '.message // empty' 2>/dev/null)
    if [[ "$message" == "Not Found" ]]; then
        return 1
    fi

    local files=$(echo "$response" | jq -r '.[] | select(.name | endswith(".yaml") or endswith(".yml")) | .download_url' 2>/dev/null)

    if [[ -n "$files" ]]; then
        while IFS= read -r download_url; do
            local filename=$(basename "$download_url")
            if curl -L -s "$download_url" -o "${output_dir}/${filename}" 2>/dev/null; then
                found=$((found + 1))
            fi
        done <<< "$files"
    fi

    echo $found
}

# ============================================================================
# Catalog Parsing Functions
# ============================================================================

parse_controller_catalog() {
    log_info "Reading controller catalog: $CATALOG_FILE"

    if [[ ! -f "$CATALOG_FILE" ]]; then
        log_error "Controller catalog not found: $CATALOG_FILE"
        exit 1
    fi

    # Check for required dependencies
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi

    if command -v yq &> /dev/null; then
        while IFS= read -r line; do
            if [[ -z "$line" || "$line" == "null" ]]; then
                continue
            fi

            local addon=$(echo "$line" | jq -r '.addon // empty')
            local namespace=$(echo "$line" | jq -r '.namespace // empty')
            local repo_url=$(echo "$line" | jq -r '.repoURL // empty')
            local version=$(echo "$line" | jq -r '.revision // empty')
            local chart=$(echo "$line" | jq -r '.chart // empty')
            local github_repo=$(echo "$line" | jq -r '.github_repo // empty')
            local github_crd_path=$(echo "$line" | jq -r '.github_crd_path // empty')

            if [[ -n "$addon" && "$addon" != "empty" && -n "$version" && "$version" != "empty" ]]; then
                CONTROLLERS+=("$addon")
                CONTROLLER_NAMESPACE["$addon"]="$namespace"
                CONTROLLER_REPO_URL["$addon"]="$repo_url"
                CONTROLLER_CURRENT_VERSION["$addon"]="$version"
                CONTROLLER_CHART_NAME["$addon"]="$chart"
                CONTROLLER_GITHUB_REPO["$addon"]="$github_repo"
                CONTROLLER_GITHUB_CRD_PATH["$addon"]="$github_crd_path"
            fi
        done < <(yq -o json eval '.' "$CATALOG_FILE" 2>/dev/null | jq -c '.[]')
    fi

    TOTAL_CONTROLLERS=${#CONTROLLERS[@]}
    log_success "Found $TOTAL_CONTROLLERS controllers"
}

get_crd_path() {
    local addon="$1"

    if [[ -n "${CONTROLLER_GITHUB_CRD_PATH[$addon]:-}" ]]; then
        echo "${CONTROLLER_GITHUB_CRD_PATH[$addon]}"
    else
        echo "helm/crds"
    fi
}

# ============================================================================
# Version Checking Functions
# ============================================================================

check_all_controller_versions() {
    log_info "Checking latest versions for all controllers..."
    echo ""

    # Check rate limit before starting
    if ! check_rate_limit; then
        log_error "Cannot proceed with version checks due to rate limit"
        exit 1
    fi

    echo "Controller,Namespace,Current Version,Latest Version,Status,Needs Upgrade" > "$VERSION_REPORT"

    for addon in "${CONTROLLERS[@]}"; do
        local current_version="${CONTROLLER_CURRENT_VERSION[$addon]}"
        local namespace="${CONTROLLER_NAMESPACE[$addon]}"
        local repo_url="${CONTROLLER_REPO_URL[$addon]}"
        local chart_name="${CONTROLLER_CHART_NAME[$addon]}"

        printf "  %-30s v%-10s ... " "$addon" "$current_version"

        local github_repo=$(get_controller_github_repo "$addon" "$repo_url" "$chart_name")

        if [[ -z "$github_repo" ]]; then
            echo -e "${RED}✗${NC} No GitHub repo"
            echo "$addon,$namespace,$current_version,N/A,❌ No GitHub repo,No" >> "$VERSION_REPORT"
            continue
        fi

        if [[ -n "${DEBUG:-}" ]]; then
            echo "" >&2
            echo "  [DEBUG] About to call get_github_latest_version with repo: $github_repo" >&2
        fi

        set +e
        get_github_latest_version "$github_repo"
        local fetch_status=$?
        local latest_version="$GITHUB_LATEST_VERSION_RESULT"
        set -e

        if [[ -n "${DEBUG:-}" ]]; then
            echo "  [DEBUG] After call: fetch_status=$fetch_status, latest_version='$latest_version', LAST_ERROR='$LAST_ERROR'" >&2
        fi

        if [[ $fetch_status -ne 0 || -z "$latest_version" ]]; then
            if [[ -n "${DEBUG:-}" ]]; then
                echo "  [DEBUG] LAST_ERROR='$LAST_ERROR'" >&2
            fi
            local error_msg="${LAST_ERROR:-Unknown error}"
            echo -e "${RED}✗${NC} $error_msg"
            echo "$addon,$namespace,$current_version,N/A,❌ $error_msg,Unknown" >> "$VERSION_REPORT"
            continue
        fi

        local comparison=$(compare_versions "$current_version" "$latest_version")

        # Show current CRD count from local directory (avoid extra API calls)
        local crd_count="-"
        local current_crd_dir="${CRD_BASE_DIR}/${addon}"
        if [[ -d "$current_crd_dir" ]]; then
            crd_count=$(count_crd_files "$current_crd_dir")
        fi
        CONTROLLER_CRD_COUNT["$addon"]=$crd_count

        case "$comparison" in
            equal)
                echo -e "${GREEN}✓${NC} v$latest_version (up to date)    CRDs: $crd_count"
                echo "$addon,$namespace,$current_version,$latest_version,✅ Up to date,No" >> "$VERSION_REPORT"
                ;;
            older)
                echo -e "${YELLOW}⬆${NC} v$latest_version ${YELLOW}(upgrade available)${NC}  CRDs: $crd_count"
                CONTROLLER_LATEST_VERSION["$addon"]="$latest_version"
                CONTROLLER_NEEDS_UPGRADE["$addon"]=1
                UPGRADES_AVAILABLE=$((UPGRADES_AVAILABLE + 1))
                echo "$addon,$namespace,$current_version,$latest_version,⬆️ Upgrade available,Yes" >> "$VERSION_REPORT"
                ;;
            newer)
                echo -e "${CYAN}↑${NC} v$latest_version (ahead)           CRDs: $crd_count"
                echo "$addon,$namespace,$current_version,$latest_version,⚠️ Ahead of latest,No" >> "$VERSION_REPORT"
                ;;
        esac
    done

    echo ""
    log_success "Version check complete - $UPGRADES_AVAILABLE upgrades available"

    if [[ $RATE_LIMITED -eq 1 ]]; then
        echo ""
        # Check current rate limit status
        check_rate_limit || true
        echo ""
        read -p "Continue with partial data? (y/n): " continue_anyway
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            exit 1
        fi
    fi
}

# ============================================================================
# CRD Utility Functions
# ============================================================================

count_crd_files() {
    local dir="$1"
    local count=0

    if [[ ! -d "$dir" ]]; then
        echo 0
        return
    fi

    shopt -s nullglob
    for file in "$dir"/*.yaml "$dir"/*.yml; do
        [[ -f "$file" ]] || continue
        local filename=$(basename "$file")
        [[ "$filename" == "kustomization.yaml" || "$filename" == "kustomization.yml" ]] && continue
        count=$((count + 1))
    done
    shopt -u nullglob

    echo $count
}

# ============================================================================
# Display Functions
# ============================================================================

display_summary() {
    echo ""
    echo "=========================================="
    echo "SUMMARY"
    echo "=========================================="
    echo ""
    echo "Total controllers checked: $TOTAL_CONTROLLERS"
    echo "Controllers needing upgrades: $UPGRADES_AVAILABLE"
    echo ""
    echo "Reports generated:"
    echo "  Version comparison: $VERSION_REPORT"
    echo ""

    if [[ $UPGRADES_AVAILABLE -gt 0 ]]; then
        echo "Controllers requiring upgrades:"
        echo "--------------------------------"
        echo "#,Controller,Namespace,Current,Latest" | safe_column -t -s','

        local index=1
        for addon in "${CONTROLLERS[@]}"; do
            if [[ -n "${CONTROLLER_NEEDS_UPGRADE[$addon]:-}" ]]; then
                local namespace="${CONTROLLER_NAMESPACE[$addon]}"
                local current="${CONTROLLER_CURRENT_VERSION[$addon]}"
                local latest="${CONTROLLER_LATEST_VERSION[$addon]}"

                echo "$index,$addon,$namespace,$current,$latest"
                index=$((index + 1))
            fi
        done | safe_column -t -s','
        echo ""
    fi
}

# ============================================================================
# Update Controller Catalog Function
# ============================================================================

prompt_and_update_catalog() {
    if [[ $UPGRADES_AVAILABLE -eq 0 ]]; then
        return
    fi

    echo "=========================================="
    echo "UPDATE CONTROLLER CATALOG"
    echo "=========================================="
    echo ""

    read -p "Enter the number(s) of controllers to upgrade (e.g., '1 3 5' or '1,3,5' or 'all'): " user_input
    echo ""

    # Build list of controllers to update
    local -a update_list=()

    if [[ "$user_input" =~ ^[Aa][Ll][Ll]$ ]]; then
        for addon in "${CONTROLLERS[@]}"; do
            if [[ -n "${CONTROLLER_NEEDS_UPGRADE[$addon]:-}" ]]; then
                update_list+=("$addon")
            fi
        done
    else
        # Normalize input: replace commas with spaces
        local normalized_input=$(echo "$user_input" | tr ',' ' ')
        local index=1
        for addon in "${CONTROLLERS[@]}"; do
            if [[ -n "${CONTROLLER_NEEDS_UPGRADE[$addon]:-}" ]]; then
                if [[ " $normalized_input " =~ " $index " ]]; then
                    update_list+=("$addon")
                fi
                index=$((index + 1))
            fi
        done
    fi

    if [[ ${#update_list[@]} -eq 0 ]]; then
        log_info "No controllers selected for upgrade"
        return
    fi

    # Dry-run mode
    if [[ $DRY_RUN -eq 1 ]]; then
        echo ""
        log_info "[DRY-RUN] Would update the following controllers:"
        for addon in "${update_list[@]}"; do
            local current="${CONTROLLER_CURRENT_VERSION[$addon]}"
            local latest="${CONTROLLER_LATEST_VERSION[$addon]}"
            echo "  $addon: $current → $latest"
        done
        return
    fi

    # Update catalog
    echo ""
    log_info "Updating catalog..."

    for addon in "${update_list[@]}"; do
        local current="${CONTROLLER_CURRENT_VERSION[$addon]}"
        local latest="${CONTROLLER_LATEST_VERSION[$addon]}"

        echo "  $addon: $current → $latest"

        # Use yq for safe YAML updates (avoids sed injection risks)
        if yq eval "(.[] | select(.addon == \"$addon\") | .revision) = \"$latest\"" -i "$CATALOG_FILE"; then
            # Verify the update was successful
            local updated_version=$(yq eval ".[] | select(.addon == \"$addon\") | .revision" "$CATALOG_FILE")
            if [[ "$updated_version" == "$latest" ]]; then
                # Track successfully updated controllers AND update in-memory version
                UPDATED_CONTROLLERS+=("$addon")
                CONTROLLER_CURRENT_VERSION["$addon"]="$latest"
            else
                log_warning "  Failed to verify update for $addon"
            fi
        else
            log_error "  Failed to update $addon in catalog"
        fi
    done

    echo ""
    log_success "Catalog updated successfully!"
}

# ============================================================================
# Download and Apply CRDs Function
# ============================================================================

download_and_apply_crds() {
    echo ""
    echo "=========================================="
    echo "DOWNLOAD AND APPLY CRDs"
    echo "=========================================="
    echo ""

    # Determine which controllers to process
    local -a controllers_to_process=()
    local mode=""

    if [[ ${#UPDATED_CONTROLLERS[@]} -gt 0 ]]; then
        local unchanged_count=$((TOTAL_CONTROLLERS - ${#UPDATED_CONTROLLERS[@]}))
        echo "Options:"
        echo "  1) Download CRDs for ${#UPDATED_CONTROLLERS[@]} upgraded controller(s) only"
        echo "  2) Refresh CRDs for ALL ${TOTAL_CONTROLLERS} controllers (${#UPDATED_CONTROLLERS[@]} upgraded + ${unchanged_count} existing)"
        echo "  3) Skip CRD download"
        echo ""
        read -p "Select option (1-3): " choice
        echo ""

        case $choice in
            1)
                controllers_to_process=("${UPDATED_CONTROLLERS[@]}")
                mode="updated"
                log_info "Downloading CRDs for upgraded controllers only"
                ;;
            2)
                controllers_to_process=("${CONTROLLERS[@]}")
                mode="all"
                log_info "Refreshing CRDs for ALL controllers in catalog"
                ;;
            3|*)
                log_info "Skipping CRD download and application"
                return
                ;;
        esac
    else
        # No updates, offer to download all
        read -p "No controllers were upgraded. Refresh CRDs for all ${TOTAL_CONTROLLERS} existing controllers? (y/n): " download_all
        echo ""

        if [[ "$download_all" == "y" || "$download_all" == "Y" ]]; then
            controllers_to_process=("${CONTROLLERS[@]}")
            mode="all"
            log_info "Downloading CRDs for ALL controllers in catalog"
        else
            log_info "Skipping CRD download and application"
            return
        fi
    fi

    clear_temp_download
    echo "Controller,Version,Download Status,CRD Count" > "$CRD_REPORT"

    # Parallel download with configurable concurrent jobs (fixes #12)
    local max_jobs=$MAX_PARALLEL_DOWNLOADS
    local job_count=0
    declare -A download_pids

    for addon in "${controllers_to_process[@]}"; do
        # Use current version from catalog (which is now updated if catalog was just modified)
        local version="${CONTROLLER_CURRENT_VERSION[$addon]}"
        local repo_url="${CONTROLLER_REPO_URL[$addon]}"
        local chart_name="${CONTROLLER_CHART_NAME[$addon]}"
        local github_repo=$(get_controller_github_repo "$addon" "$repo_url" "$chart_name")
        local crd_dir="${TEMP_DOWNLOAD_DIR}/${addon}"
        mkdir -p "$crd_dir"

        if [[ -z "$github_repo" ]]; then
            log_warning "  No GitHub repo for $addon - skipping"
            echo "$addon,$version,No GitHub repo,0" >> "$CRD_REPORT"
            continue
        fi

        # Wait if we've hit max concurrent jobs
        while [[ $job_count -ge $max_jobs ]]; do
            wait -n 2>/dev/null || true
            job_count=$((job_count - 1))
        done

        # Download in background
        (
            local crd_path=$(get_crd_path "$addon")
            set +e
            local count=$(download_crds_from_github "$github_repo" "$version" "$crd_path" "$crd_dir" 2>/dev/null)
            set -e

            if [[ -z "$count" || "$count" == "0" ]]; then
                echo "$addon,$version,Download failed,0" >> "$CRD_REPORT"
            else
                echo "$addon,$version,Success,$count" >> "$CRD_REPORT"
            fi
        ) &

        download_pids["$addon"]=$!
        job_count=$((job_count + 1))
    done

    # Wait for all downloads to complete
    log_info "Waiting for all downloads to complete..."
    wait

    # Now apply the downloaded CRDs
    echo ""
    log_info "Applying downloaded CRDs..."
    for addon in "${controllers_to_process[@]}"; do
        local version="${CONTROLLER_CURRENT_VERSION[$addon]}"
        local crd_dir="${TEMP_DOWNLOAD_DIR}/${addon}"

        if [[ ! -d "$crd_dir" ]]; then
            continue
        fi

        local count=$(count_crd_files "$crd_dir")
        if [[ $count -eq 0 ]]; then
            continue
        fi

        log_info "Applying $count CRDs for $addon v$version"

        # Create kustomization.yaml
        {
            echo "apiVersion: kustomize.config.k8s.io/v1beta1"
            echo "kind: Kustomization"
            echo "resources:"
            shopt -s nullglob
            for file in "$crd_dir"/*.yaml "$crd_dir"/*.yml; do
                [[ -f "$file" ]] || continue
                local filename=$(basename "$file")
                [[ "$filename" == "kustomization.yaml" || "$filename" == "kustomization.yml" ]] && continue
                echo "  - $filename"
            done
            shopt -u nullglob
        } > "$crd_dir/kustomization.yaml"

        # Replace CRD directory
        local target_dir="${CRD_BASE_DIR}/${addon}"
        rm -rf "$target_dir"
        mv "$crd_dir" "$target_dir"

        log_success "  Applied $count CRDs to $target_dir"
    done

    echo ""
    log_success "CRDs downloaded and applied successfully!"
}

# ============================================================================
# Help/Usage Function
# ============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Controller Version & CRD Update Script

OPTIONS:
    --dry-run              Show what would be updated without making changes
    --help, -h             Show this help message

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN           GitHub personal access token (avoids rate limits)
    API_TIMEOUT            GitHub API request timeout in seconds (default: 10)
    API_CONNECT_TIMEOUT    GitHub API connection timeout in seconds (default: 5)
    MAX_PARALLEL_DOWNLOADS Maximum concurrent CRD downloads (default: 5)

EXAMPLES:
    # Normal run
    $0

    # Dry-run to preview changes
    $0 --dry-run

    # With custom settings
    GITHUB_TOKEN=ghp_xxx MAX_PARALLEL_DOWNLOADS=3 $0

EOF
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=1
                log_info "Running in DRY-RUN mode - no changes will be made"
                echo ""
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done

    echo "=========================================="
    echo "Controller Version & CRD Update Script"
    echo "=========================================="
    echo ""

    # Step 1: Parse catalog
    parse_controller_catalog
    echo ""

    # Step 2: Check versions
    check_all_controller_versions
    echo ""

    # Step 3: Display summary of available upgrades
    display_summary

    # Step 4: Prompt and update catalog
    prompt_and_update_catalog

    # Step 5: Display summary of what was updated
    if [[ ${#UPDATED_CONTROLLERS[@]} -gt 0 ]]; then
        echo ""
        echo "=========================================="
        echo "UPDATED CONTROLLERS"
        echo "=========================================="
        echo ""
        echo "Successfully updated ${#UPDATED_CONTROLLERS[@]} controller(s) in catalog:"
        for addon in "${UPDATED_CONTROLLERS[@]}"; do
            echo "  - $addon: ${CONTROLLER_CURRENT_VERSION[$addon]} → ${CONTROLLER_LATEST_VERSION[$addon]}"
        done
        echo ""
    fi

    # Step 6: Download and apply CRDs
    download_and_apply_crds

    echo ""
    log_success "Script complete!"
}

# Run main function
main "$@"
