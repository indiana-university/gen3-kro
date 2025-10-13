#!/usr/bin/env bash
# bootstrap/scripts/connect-cluster.sh
# Updates kubeconfig to connect to the EKS cluster using Terragrunt outputs

set -euo pipefail
IFS=$'\n\t'

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

# Source logging library
source "${SCRIPT_DIR}/lib-logging.sh"

# Configuration
LOG_DIR="${REPO_ROOT}/outputs/logs"
LIVE_DIR="${REPO_ROOT}/terraform/live"

# Create directories
mkdir -p "$LOG_DIR"

# Set log file
LOG_FILE="${LOG_DIR}/connect-cluster-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

log_info "========================================="
log_info "Connect to EKS Cluster - gen3-kro"
log_info "========================================="

# Change to live directory
cd "$LIVE_DIR"

# Get cluster name and region from Terragrunt outputs
log_info "Retrieving cluster information from Terragrunt..."

CLUSTER_NAME=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
AWS_REGION=$(terragrunt output -raw aws_region 2>/dev/null || echo "us-east-1")
AWS_PROFILE=$(terragrunt output -raw aws_profile 2>/dev/null || echo "default")

if [[ -z "$CLUSTER_NAME" ]]; then
  log_error "Could not retrieve cluster name from Terragrunt outputs"
  log_info "Make sure you have run 'terragrunt apply' first"
  exit 1
fi

log_info "Cluster Name: $CLUSTER_NAME"
log_info "AWS Region: $AWS_REGION"
log_info "AWS Profile: $AWS_PROFILE"

# Update kubeconfig
log_info "Updating kubeconfig..."
aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --alias "$CLUSTER_NAME"

log_success "✓ Kubeconfig updated successfully"
log_info "Context: $CLUSTER_NAME"

# Verify connectivity
log_info "Verifying kubectl connectivity..."
if kubectl cluster-info --context "$CLUSTER_NAME" >/dev/null 2>&1; then
  log_success "✓ Successfully connected to cluster"
else
  log_warn "Could not verify cluster connectivity"
fi

log_success "========================================="
log_success "✓ Setup complete!"
log_success "========================================="
log_info "You can now use kubectl with context: $CLUSTER_NAME"
log_info "Example: kubectl get pods -A --context $CLUSTER_NAME"
