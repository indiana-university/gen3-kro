#!/usr/bin/env bash
###############################################################################
# Connect Cluster Script
# Updates kubeconfig to connect to the EKS cluster and configures ArgoCD access
###############################################################################

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Configuration and Setup
###############################################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
LOG_DIR="${REPO_ROOT}/outputs/logs"
STACK_DIR="${STACK_DIR:-${REPO_ROOT}/live/aws/us-east-1/gen3-kro-dev}"

source "${SCRIPT_DIR}/lib-logging.sh"

###############################################################################
# Argument Parsing
###############################################################################
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

###############################################################################
# Main Execution
###############################################################################
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/connect-cluster-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

log_info "========================================="
log_info "Connect to EKS Cluster - gen3-kro"
log_info "========================================="

###############################################################################
# Retrieve Cluster Information from secrets.yaml
###############################################################################
SECRETS_FILE="${STACK_DIR}/secrets.yaml"

if [[ ! -f "$SECRETS_FILE" ]]; then
  log_error "Secrets file not found: $SECRETS_FILE"
  log_info "Make sure you have created secrets.yaml in your stack directory"
  exit 1
fi

log_info "Reading cluster configuration from secrets.yaml..."

# Parse secrets.yaml to get cluster info
CLUSTER_NAME=$(grep -A 2 "csoc:" "$SECRETS_FILE" | grep "cluster_name:" | awk '{print $2}' | tr -d '"' || echo "")
AWS_REGION=$(grep -A 5 "provider:" "$SECRETS_FILE" | grep "region:" | head -1 | awk '{print $2}' | tr -d '"' || echo "us-east-1")
AWS_PROFILE=$(grep -A 5 "provider:" "$SECRETS_FILE" | grep "profile:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")

if [[ -z "$CLUSTER_NAME" ]]; then
  log_error "Could not retrieve cluster name from secrets.yaml"
  log_info "Make sure your secrets.yaml is properly configured"
  exit 1
fi

log_info "Cluster Name: $CLUSTER_NAME"
log_info "AWS Region: $AWS_REGION"
log_info "AWS Profile: $AWS_PROFILE"

###############################################################################
# Update Kubeconfig
###############################################################################
log_info "Updating kubeconfig..."

# Build AWS CLI command with optional profile
AWS_CMD="aws eks update-kubeconfig --name \"$CLUSTER_NAME\" --region \"$AWS_REGION\" --alias \"$CLUSTER_NAME\""
if [[ -n "$AWS_PROFILE" ]]; then
  AWS_CMD="$AWS_CMD --profile \"$AWS_PROFILE\""
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "DRY RUN: would run: $AWS_CMD"
  log_info "DRY RUN: would verify kubectl connectivity: kubectl cluster-info --context \"$CLUSTER_NAME\""
else
  if [[ -n "$AWS_PROFILE" ]]; then
    aws eks update-kubeconfig \
      --name "$CLUSTER_NAME" \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --alias "$CLUSTER_NAME"
  else
    aws eks update-kubeconfig \
      --name "$CLUSTER_NAME" \
      --region "$AWS_REGION" \
      --alias "$CLUSTER_NAME"
  fi

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

###############################################################################
# ArgoCD Access Information
###############################################################################
log_info ""
log_info "Retrieving ArgoCD access information..."

# Get ArgoCD password from Kubernetes secret (not Terragrunt output)
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "")

# Get ArgoCD LoadBalancer hostname from Kubernetes service
ARGOCD_LB_URL=$(kubectl -n argocd get svc argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [[ -n "$ARGOCD_PASSWORD" ]]; then
  log_success "✓ ArgoCD Admin Password: $ARGOCD_PASSWORD"

  # Save password to outputs directory for future reference
  mkdir -p "${REPO_ROOT}/outputs/argo"
  echo "$ARGOCD_PASSWORD" > "${REPO_ROOT}/outputs/argo/admin-password.txt"
  echo "$ARGOCD_LB_URL" >> "${REPO_ROOT}/outputs/argo/admin-password.txt"
  chmod 600 "${REPO_ROOT}/outputs/argo/admin-password.txt"
  log_info "  (saved to outputs/argo/admin-password.txt)"
else
  log_info "ArgoCD password not available (ArgoCD might not be deployed yet)"
fi

if [[ -n "$ARGOCD_LB_URL" ]]; then
  log_success "✓ ArgoCD LoadBalancer URL: https://$ARGOCD_LB_URL"
  log_info "  Username: admin"
  log_info "  Password: $ARGOCD_PASSWORD"

  # Try to login to ArgoCD CLI
  if command -v argocd >/dev/null 2>&1 && [[ -n "$ARGOCD_PASSWORD" ]]; then
    log_info "Logging in to ArgoCD CLI..."
    if argocd login "$ARGOCD_LB_URL" --username admin --password "$ARGOCD_PASSWORD" --insecure >/dev/null 2>&1; then
      log_success "✓ ArgoCD CLI logged in successfully"
    else
      log_warn "Could not login to ArgoCD CLI (server might still be starting)"
    fi
  fi
else
  log_info "ArgoCD LoadBalancer not available (using port-forward instead)"
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

###############################################################################
# End of File
###############################################################################
