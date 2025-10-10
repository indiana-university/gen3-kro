#!/usr/bin/env bash
# bootstrap/terragrunt-wrapper.sh
# Simplified wrapper for Terragrunt operations
# Replaces the complex init-tf.sh script with centralized configuration

set -euo pipefail
IFS=$'\n\t'

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Source logging library
# shellcheck source=./bootstrap/scripts/lib-logging.sh
source "${SCRIPT_DIR}/scripts/lib-logging.sh"

# Configuration
CONFIG_FILE="${REPO_ROOT}/config/config.yaml"
LIVE_DIR="${REPO_ROOT}/terraform/live"
LOG_DIR="${REPO_ROOT}/outputs/logs"

# Create log directory
mkdir -p "$LOG_DIR"

# Set log file
LOG_FILE="${LOG_DIR}/terragrunt-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

# Validation function
validate_config() {
  local errors=0

  log_info "Validating configuration..."

  # Check config file exists
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    ((errors++))
  fi

  # Check required commands
  for cmd in terragrunt terraform kubectl helm jq aws; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Required command not found: $cmd"
      ((errors++))
    fi
  done

  # Check for yq (YAML processor)
  if ! command -v yq >/dev/null 2>&1; then
    log_warn "yq not found - using python for YAML validation"
    # Try python as fallback
    if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
      log_error "Neither yq nor python found for YAML processing"
      ((errors++))
    fi
  fi

  # Validate YAML syntax using yq or python
  if command -v yq >/dev/null 2>&1; then
    if ! yq eval '.' "$CONFIG_FILE" >/dev/null 2>&1; then
      log_error "Invalid YAML syntax in: $CONFIG_FILE"
      ((errors++))
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>/dev/null; then
      log_error "Invalid YAML syntax in: $CONFIG_FILE"
      ((errors++))
    fi
  fi

  # Check live directory exists
  if [[ ! -d "$LIVE_DIR" ]]; then
    log_error "Live environments directory not found: $LIVE_DIR"
    ((errors++))
  fi

  if ((errors > 0)); then
    log_error "Configuration validation failed with $errors error(s)"
    return 1
  fi

  log_success "✓ Configuration validation passed"
  return 0
}

# Validate AWS credentials
validate_aws_credentials() {
  local profile="$1"

  log_info "Validating AWS credentials for profile: $profile"

  if ! aws configure list --profile "$profile" >/dev/null 2>&1; then
    log_error "AWS profile not configured: $profile"
    return 1
  fi

  # Try to get caller identity
  if ! aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
    log_error "AWS credentials invalid or expired for profile: $profile"
    return 1
  fi

  log_success "✓ AWS credentials validated for: $profile"
  return 0
}

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") ENVIRONMENT COMMAND [OPTIONS]

ENVIRONMENT:
  prod        Production environment
  staging     Staging environment
  dr          Disaster recovery environment

COMMAND:
  plan        Generate execution plan
  apply       Apply changes (auto-approved)
  destroy     Destroy infrastructure (auto-approved)
  validate    Validate Terragrunt configuration
  init        Initialize Terragrunt
  output      Show outputs
  graph       Generate dependency graph
  show        Show current state

OPTIONS:
  -y, --yes        Deprecated (auto-approve is now default)
  -v, --verbose    Enable verbose logging
  --debug          Enable Terraform debug logging (TF_LOG=DEBUG)

EXAMPLES:
  # Validate and plan production
  $(basename "$0") prod validate
  $(basename "$0") prod plan

  # Apply changes to staging
  $(basename "$0") staging apply

  # Destroy production (requires confirmation)
  $(basename "$0") prod destroy

  # Run all environments
  cd terraform/live
  terragrunt run-all plan

  # Show dependency graph
  $(basename "$0") prod graph

ENVIRONMENT VARIABLES:
  TF_LOG          Terraform logging level (DEBUG, INFO, WARN, ERROR)
  VERBOSE         Enable verbose output (1 or 0)

EOF
}

# Confirmation prompt for destructive operations
confirm_action() {
  local environment="$1"
  local action="$2"
  local auto_approve="${3:-false}"

  if [[ "$auto_approve" == "true" ]]; then
    log_notice "Auto-approve enabled, skipping confirmation"
    return 0
  fi

  log_warn "⚠️  DESTRUCTIVE OPERATION"
  log_warn "Environment: $environment"
  log_warn "Action: $action"
  echo ""

  read -r -p "Type 'YES' to confirm: " confirmation

  if [[ "$confirmation" != "YES" ]]; then
    log_error "Operation cancelled by user"
    return 1
  fi

  log_notice "Confirmation received, proceeding..."
  return 0
}

# Main execution
main() {
  local auto_approve=false
  local VERBOSE=false
  local DEBUG=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes)
        auto_approve=true
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        export VERBOSE
        shift
        ;;
      --debug)
        DEBUG=true
        export TF_LOG=DEBUG
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -lt 2 ]]; then
    usage
    exit 1
  fi

  local environment="$1"
  local command="$2"

  log_info "========================================="
  log_info "Terragrunt Wrapper - gen3-kro"
  log_info "========================================="
  log_info "Environment: $environment"
  log_info "Command: $command"
  log_info "Log file: $LOG_FILE"
  log_info "========================================="

  # Validate configuration
  validate_config || exit 1

  # Environment directory
  local env_dir="${LIVE_DIR}/${environment}"

  if [[ ! -d "$env_dir" ]]; then
    log_error "Environment directory not found: $env_dir"
    log_info "Available environments:"
    for env in "$LIVE_DIR"/*; do
      if [[ -d "$env" ]]; then
        log_info "  - $(basename "$env")"
      fi
    done
    exit 1
  fi

  # Change to environment directory
  cd "$env_dir"
  log_info "Working directory: $env_dir"

  # Execute Terragrunt command
  case "$command" in
    plan)
      log_info "Generating execution plan..."
      terragrunt plan -out=tfplan
      log_success "✓ Plan generated: tfplan"
      log_notice "Review the plan, then run: $(basename "$0") $environment apply"
      ;;

    apply)
      log_info "Applying changes..."
      if [[ -f "tfplan" ]]; then
        log_info "Using existing plan file: tfplan"
        terragrunt apply tfplan
        rm -f tfplan
      else
        log_warn "No plan file found, generating new plan and applying..."
        terragrunt apply -auto-approve
      fi
      log_success "✓ Changes applied successfully"

      # Update kubeconfig after successful apply
      log_info "Updating kubeconfig for environment: $environment"
      if [[ -f "${SCRIPT_DIR}/scripts/connect-cluster.sh" ]]; then
        bash "${SCRIPT_DIR}/scripts/connect-cluster.sh" "$environment"
        log_success "✓ Kubeconfig updated successfully"
      else
        log_warn "connect-cluster.sh not found, skipping kubeconfig update"
        log_notice "Run manually: ./bootstrap/scripts/connect-cluster.sh $environment"
      fi
      ;;

    destroy)
      log_warn "Destroying infrastructure..."
      terragrunt destroy -auto-approve
      log_success "✓ Infrastructure destroyed"
      ;;

    validate)
      log_info "Validating Terragrunt configuration..."
      terragrunt validate
      log_success "✓ Configuration is valid"
      ;;

    init)
      log_info "Initializing Terragrunt..."
      terragrunt init
      log_success "✓ Terragrunt initialized"
      ;;

    output)
      log_info "Showing outputs..."
      terragrunt output
      ;;

    graph)
      log_info "Generating dependency graph..."
      local graph_file="${REPO_ROOT}/outputs/terragrunt-graph-${environment}.dot"
      terragrunt graph-dependencies > "$graph_file"
      log_success "✓ Dependency graph saved to: $graph_file"
      log_notice "Visualize with: dot -Tpng $graph_file -o ${graph_file%.dot}.png"
      ;;

    show)
      log_info "Showing current state..."
      if [[ -f "tfplan" ]]; then
        terragrunt show tfplan
      else
        terragrunt show
      fi
      ;;

    *)
      log_error "Unknown command: $command"
      usage
      exit 1
      ;;
  esac

  log_success "✓ Command completed successfully"
  log_info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
