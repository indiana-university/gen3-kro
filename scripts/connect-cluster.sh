#!/usr/bin/env bash
# scripts/connect-cluster.sh
# Updates kubeconfig to connect to the EKS cluster using Terragrunt outputs

set -euo pipefail
IFS=$'\n\t'

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Source logging library
source "${SCRIPT_DIR}/lib-logging.sh"

# Default dry-run to off. Use --dry-run or -n to enable.
DRY_RUN=0
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Configuration
LOG_DIR="${REPO_ROOT}/outputs/logs"
TERRAGRUNT_DIR="${REPO_ROOT}/live/aws/us-east-1/gen3-kro-dev"

# Create directories
mkdir -p "$LOG_DIR"

# Set log file
LOG_FILE="${LOG_DIR}/connect-cluster-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

log_info "========================================="
log_info "Connect to EKS Cluster - gen3-kro"
log_info "========================================="

# Change to terragrunt directory
cd "$TERRAGRUNT_DIR"

# Get cluster name and region from Terragrunt outputs
log_info "Retrieving cluster information from Terragrunt..."

CLUSTER_NAME=$(terragrunt output -raw cluster_name 2>/dev/null || echo "")
AWS_REGION="us-east-1"  # Hard-coded for now, can make dynamic later
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
if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "DRY RUN: would run: aws eks update-kubeconfig --name \"$CLUSTER_NAME\" --region \"$AWS_REGION\" --profile \"$AWS_PROFILE\" --alias \"$CLUSTER_NAME\""
  log_info "DRY RUN: would verify kubectl connectivity: kubectl cluster-info --context \"$CLUSTER_NAME\""
else
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
fi

# Get ArgoCD credentials if available
log_info ""
log_info "Retrieving ArgoCD access information..."
ARGOCD_PASSWORD=$(terragrunt output -raw argocd_admin_password 2>/dev/null || echo "")
ARGOCD_LB_URL=$(terragrunt output -raw argocd_loadbalancer_url 2>/dev/null || echo "")

if [[ -n "$ARGOCD_PASSWORD" ]]; then
  log_success "✓ ArgoCD Admin Password: $ARGOCD_PASSWORD"
else
  log_info "ArgoCD password not available (might not be deployed yet)"
fi

if [[ -n "$ARGOCD_LB_URL" && "$ARGOCD_LB_URL" != "null" ]]; then
  log_success "✓ ArgoCD LoadBalancer URL: https://$ARGOCD_LB_URL"
else
  log_info "ArgoCD LoadBalancer URL not available (using port-forward instead)"
  log_info "To access ArgoCD via port-forward:"
  log_info "  kubectl port-forward -n argocd svc/argo-cd-argocd-server 8080:443"
  log_info "  Then visit: https://localhost:8080"
fi

log_success "========================================="
log_success "✓ Setup complete!"
log_success "========================================="
log_info "You can now use kubectl with context: $CLUSTER_NAME"
log_info "Example: kubectl get pods -A --context $CLUSTER_NAME"

if [[ -n "$ARGOCD_PASSWORD" ]]; then
  log_info ""
  log_info "ArgoCD Access:"
  log_info "  Username: admin"
  log_info "  Password: $ARGOCD_PASSWORD"
  if [[ -n "$ARGOCD_LB_URL" && "$ARGOCD_LB_URL" != "null" ]]; then
    log_info "  URL: https://$ARGOCD_LB_URL"
  fi
fi
