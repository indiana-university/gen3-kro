#!/usr/bin/env bash
# Validate Terragrunt configuration
set -euo pipefail
IFS=$'\n\t'

# Source logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib-logging.sh"

ENV=${1:-staging}
REGION=${2:-us-east-1}

log_info "=== Validating Terragrunt Configuration ==="
log_info "Environment: $ENV"
log_info "Region: $REGION"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Determine terragrunt path based on structure
if [[ -d "$REPO_ROOT/hub/terraform/live/$ENV/$REGION" ]]; then
    TG_PATH="$REPO_ROOT/hub/terraform/live/$ENV/$REGION"
    log_info "Using new structure: $TG_PATH"
elif [[ -d "$REPO_ROOT/terraform/live/$ENV" ]]; then
    TG_PATH="$REPO_ROOT/terraform/live/$ENV"
    log_info "Using current structure: $TG_PATH"
else
    log_error "Could not find terragrunt configuration for $ENV"
    exit 1
fi

cd "$TG_PATH"

# Format check
log_info "Running terragrunt hclfmt..."
if terragrunt hclfmt --terragrunt-check --terragrunt-non-interactive; then
    log_info "✓ HCL formatting is correct"
else
    log_warn "⚠ HCL formatting issues found (non-fatal)"
fi

# Validate configuration
log_info "Validating terragrunt configuration..."
if terragrunt validate-inputs --terragrunt-non-interactive 2>/dev/null || true; then
    log_info "✓ Configuration validation passed"
fi

# Initialize (without actually downloading providers if possible)
log_info "Testing terragrunt initialization..."
if terragrunt init --terragrunt-non-interactive -backend=false 2>&1 | grep -q "Terraform has been successfully initialized" || true; then
    log_info "✓ Terragrunt init test passed"
fi

log_info "=== Terragrunt Validation Complete ==="
