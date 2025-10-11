#!/usr/bin/env bash
# bootstrap/scripts/connect-cluster.sh
# Post-deployment script to connect kubectl and retrieve ArgoCD credentials
#
# Usage:
#   ./bootstrap/scripts/connect-cluster.sh <environment>
#
# Example:
#   ./bootstrap/scripts/connect-cluster.sh staging
#   ./bootstrap/scripts/connect-cluster.sh prod

set -euo pipefail

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

# Source logging library
# shellcheck source=./bootstrap/scripts/lib-logging.sh
source "${SCRIPT_DIR}/lib-logging.sh"

# Configuration
CONFIG_FILE="${REPO_ROOT}/config/config.yaml"
OUTPUTS_DIR="${REPO_ROOT}/outputs"

# Create outputs directory structure
mkdir -p "$OUTPUTS_DIR/argo"

# Log file
LOG_FILE="${OUTPUTS_DIR}/logs/connect-cluster-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE
mkdir -p "$(dirname "$LOG_FILE")"

###################################################################################################################################################
# Helper Functions
###################################################################################################################################################

usage() {
  cat <<EOF
Usage: $(basename "$0") ENVIRONMENT

Connect kubectl to EKS cluster and retrieve ArgoCD credentials

ENVIRONMENT:
  staging     Connect to staging cluster (gen3-kro-hub-staging)
  prod        Connect to production cluster (gen3-kro-hub)

EXAMPLES:
  # Connect to staging
  $(basename "$0") staging

  # Connect to production
  $(basename "$0") prod

OUTPUTS:
  - Updates ~/.kube/config with cluster context
  - Saves ArgoCD credentials to: outputs/argo/argocd-credentials.txt
  - Displays ArgoCD URL, username, and password

REQUIREMENTS:
  - AWS CLI configured with appropriate profile
  - kubectl installed
  - argocd CLI installed (optional, for login)
  - EKS cluster already deployed

EOF
}

# Parse YAML config (requires yq or python)
get_config_value() {
  local key="$1"

  if command -v yq >/dev/null 2>&1; then
    yq eval "$key" "$CONFIG_FILE"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import yaml; config=yaml.safe_load(open('$CONFIG_FILE')); print(config$(echo "$key" | sed 's/\./ /g' | awk '{for(i=1;i<=NF;i++) printf "['\''%s'\'']", $i}'))"
  else
    log_error "Neither yq nor python3 found. Cannot parse YAML config."
    exit 1
  fi
}

###################################################################################################################################################
# Main Script
###################################################################################################################################################

main() {
  # Parse arguments
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local environment="$1"
  shift || true

  # Support optional --dry-run flag (stops before making external calls)
  local DRY_RUN=false
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      DRY_RUN=true
    fi
  done

  log_info "========================================="
  log_info "Connect to EKS Cluster - gen3-kro"
  log_info "========================================="
  log_info "Environment: $environment"
  log_info "========================================="

  # Load configuration from config.yaml
  log_info "Loading configuration from: $CONFIG_FILE"

  # Merge base + environment overlay into config/config.yaml if needed
  merge_configs() {
    local env="$1"
    local base="$REPO_ROOT/config/base.yaml"
    local overlay="$REPO_ROOT/config/environments/${env}.yaml"
    local out="$REPO_ROOT/config/config.yaml"

    if [[ ! -f "$base" ]]; then
      log_error "Base config not found: $base"
      return 1
    fi
    if [[ ! -f "$overlay" ]]; then
      log_error "Environment overlay not found: $overlay"
      return 1
    fi

    # Use yq if available
    if command -v yq >/dev/null 2>&1; then
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$base" "$overlay" > "$out"
      log_info "Merged $base + $overlay -> $out (via yq)"
      return 0
    fi

    # Fall back to Python merge
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<PY
import sys, yaml
from pathlib import Path
base = yaml.safe_load(Path(r"$base").read_text()) or {}
overlay = yaml.safe_load(Path(r"$overlay").read_text()) or {}

def deep_merge(a, b):
    for k, v in b.items():
        if k in a and isinstance(a[k], dict) and isinstance(v, dict):
            deep_merge(a[k], v)
        else:
            a[k] = v

deep_merge(base, overlay)
Path(r"$out").write_text(yaml.safe_dump(base, sort_keys=False))
print(f"Merged {r'$base'} + {r'$overlay'} -> {r'$out'} (via python)")
PY
      return 0
    fi

    log_error "Neither yq nor python3 available to merge configs"
    return 1
  }

  if ! merge_configs "$environment"; then
    log_error "Failed to prepare merged config"
    exit 1
  fi

  local hub_profile
  local hub_region
  local cluster_base_name

  hub_profile=$(get_config_value '.hub.aws_profile')
  hub_region=$(get_config_value '.hub.aws_region')
  cluster_base_name=$(get_config_value '.hub.cluster_name')

  # If dry-run, print the resolved values and exit before making external calls
  if [[ "$DRY_RUN" == true ]]; then
    log_info "--- DRY RUN: resolved config values ---"
    log_info "hub_profile: $hub_profile"
    log_info "hub_region: $hub_region"
    log_info "cluster_base_name: $cluster_base_name"
    log_info "Using merged config: $CONFIG_FILE"
    echo
    log_info "Dry-run complete; no external commands were executed."
    return 0
  fi

  # Determine full cluster name based on environment
  local cluster_name
  if [[ "$environment" == "prod" ]]; then
    cluster_name="$cluster_base_name"
  else
    cluster_name="${cluster_base_name}-${environment}"
  fi

  log_info "Cluster name: $cluster_name"
  log_info "AWS profile: $hub_profile"
  log_info "AWS region: $hub_region"

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 1. Verify AWS credentials
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Verifying AWS credentials..."

  if ! aws sts get-caller-identity --profile "$hub_profile" >/dev/null 2>&1; then
    log_error "AWS credentials invalid or expired for profile: $hub_profile"
    exit 1
  fi

  log_success "✓ AWS credentials validated"

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 2. Verify EKS cluster exists
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Verifying EKS cluster exists..."

  if ! aws eks describe-cluster --name "$cluster_name" --region "$hub_region" --profile "$hub_profile" >/dev/null 2>&1; then
    log_error "EKS cluster not found: $cluster_name"
    log_error "Please deploy the cluster first with: ./bootstrap/terragrunt-wrapper.sh $environment apply"
    exit 1
  fi

  log_success "✓ EKS cluster found: $cluster_name"

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 3. Connect to the cluster and update kubeconfig
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Attempting to load kubeconfig (if provided in outputs)..."

  # Allow the repository configuration to point to a kubeconfig directory
  local kube_dir
  local kube_dir_abs
  local kube_file
  local skip_aws_update=false

  # Prefer deployment.kubeconfig_dir, fall back to paths.kubeconfig_dir, then default
  kube_dir=$(get_config_value '.deployment.kubeconfig_dir' 2>/dev/null || true)
  if [[ -z "$kube_dir" ]]; then
    kube_dir=$(get_config_value '.paths.kubeconfig_dir' 2>/dev/null || true)
  fi
  if [[ -z "$kube_dir" ]]; then
    kube_dir="outputs/kube"
  fi

  # Make absolute path if relative
  if [[ "$kube_dir" = /* ]]; then
    kube_dir_abs="$kube_dir"
  else
    kube_dir_abs="$REPO_ROOT/$kube_dir"
  fi

  if [[ -d "$kube_dir_abs" ]]; then
    # Try to find a kubeconfig file matching the cluster name first (case-insensitive), otherwise pick the first file
    kube_file=""
    # Use find to safely enumerate files (handles special chars and spaces)
    # Check if there is at least one regular file inside the directory
    if IFS= read -r -d '' _ < <(find "$kube_dir_abs" -maxdepth 1 -type f -print0 2>/dev/null); then
      shopt -s nocasematch || true
      first=""
      while IFS= read -r -d '' f; do
        if [[ -z "$first" ]]; then
          first="$f"
        fi
        filename=$(basename "$f")
        if [[ "$filename" == *"$cluster_name"* ]]; then
          kube_file="$f"
          break
        fi
      done < <(find "$kube_dir_abs" -maxdepth 1 -type f -print0 2>/dev/null)
      shopt -u nocasematch || true

      # Fallback to first file found if no match
      if [[ -z "$kube_file" ]]; then
        kube_file="$first"
      fi
    fi

    if [[ -n "$kube_file" && -f "$kube_file" ]]; then
      log_info "Found kubeconfig file: $kube_file"

      # Export KUBECONFIG so kubectl uses this file (merged with existing config)
      export KUBECONFIG="$kube_file:$HOME/.kube/config"

      # Try to detect a context matching the cluster name inside the kubeconfig
      local candidate_context
      candidate_context=$(kubectl --kubeconfig="$kube_file" config get-contexts -o name 2>/dev/null | grep -i "${cluster_name}" || true)
      candidate_context=$(echo "$candidate_context" | head -n1 || true)

      if [[ -n "$candidate_context" ]]; then
        log_success "✓ Loaded kubeconfig and found context: $candidate_context"

        # Verify connectivity using the kubeconfig/context we found
        if kubectl cluster-info --context "$candidate_context" >/dev/null 2>&1; then
          log_success "✓ Cluster connectivity verified using provided kubeconfig"
          # Use the context name as the cluster context going forward
          cluster_name="$candidate_context"
          skip_aws_update=true
        else
          log_warn "Provided kubeconfig contains a context ($candidate_context) but cluster is not reachable; will fall back to aws eks update-kubeconfig"
        fi
      else
        log_warn "Kubeconfig found but no context matching '$cluster_name' inside; will run aws eks update-kubeconfig to ensure auth is configured"
      fi
    fi
  else
    log_info "No kubeconfig directory found at: $kube_dir_abs"
  fi

  if [[ "$skip_aws_update" != true ]]; then
    log_info "Updating kubeconfig using AWS EKS..."

    if aws eks update-kubeconfig \
      --name "$cluster_name" \
      --alias "$cluster_name" \
      --region "$hub_region" \
      --profile "$hub_profile"; then
      log_success "✓ Kubeconfig updated successfully"
      log_info "Context name: $cluster_name"
    else
      log_error "Failed to update kubeconfig"
      exit 1
    fi
  else
    log_info "Skipping aws eks update-kubeconfig because a working kubeconfig was loaded from: $kube_file"
  fi

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 4. Verify cluster connectivity
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Testing cluster connectivity..."

  if ! kubectl cluster-info --context "$cluster_name" >/dev/null 2>&1; then
    log_error "Cannot connect to cluster. Check your AWS credentials and network connectivity."
    exit 1
  fi

  log_success "✓ Cluster connectivity verified"

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 5. Wait for ArgoCD to be ready
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Checking ArgoCD deployment status..."

  local max_wait=300
  local wait_count=0

  while [[ $wait_count -lt $max_wait ]]; do
    if kubectl get namespace argocd --context "$cluster_name" >/dev/null 2>&1; then
      if kubectl get pods -n argocd --context "$cluster_name" | grep -q "argocd-server"; then
        log_success "✓ ArgoCD namespace and pods found"
        break
      fi
    fi

    if [[ $wait_count -eq 0 ]]; then
      log_warn "ArgoCD not yet deployed, waiting..."
    fi

    sleep 5
    ((wait_count+=5))
  done

  if [[ $wait_count -ge $max_wait ]]; then
    log_error "Timeout waiting for ArgoCD to be deployed"
    log_error "ArgoCD may not be installed. Check Terraform outputs."
    exit 1
  fi

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 6. Wait for ArgoCD server to be ready
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Waiting for ArgoCD server to be ready..."

  if ! kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n argocd --context "$cluster_name" 2>&1 | tee -a "$LOG_FILE"; then
    log_warn "ArgoCD server deployment not yet ready, but continuing..."
  else
    log_success "✓ ArgoCD server is ready"
  fi

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 7. Collect the ArgoCD host
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Retrieving ArgoCD server address..."

  local argo_host
  local wait_lb=0

  while [[ $wait_lb -lt 120 ]]; do
    argo_host=$(kubectl get svc argocd-server -n argocd --context "$cluster_name" \
                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -n "$argo_host" && "$argo_host" != "null" ]]; then
      log_success "✓ ArgoCD host: $argo_host"
      break
    fi

    if [[ $wait_lb -eq 0 ]]; then
      log_warn "Waiting for LoadBalancer to be provisioned..."
    fi

    sleep 5
    ((wait_lb+=5))
  done

  if [[ -z "$argo_host" || "$argo_host" == "null" ]]; then
    log_warn "LoadBalancer hostname not available yet"
    log_info "You can retrieve it later with:"
    log_info "  kubectl get svc argocd-server -n argocd --context $cluster_name"
    argo_host="<pending>"
  fi

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 8. Collect the ArgoCD credentials
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "Retrieving ArgoCD credentials..."

  local argo_username="admin"
  local argo_pass

  # Wait for secret to be created
  local wait_secret=0
  while [[ $wait_secret -lt 60 ]]; do
    if kubectl get secret argocd-initial-admin-secret -n argocd --context "$cluster_name" >/dev/null 2>&1; then
      argo_pass=$(kubectl get secret argocd-initial-admin-secret -n argocd --context "$cluster_name" \
                  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

      if [[ -n "$argo_pass" ]]; then
        log_success "✓ ArgoCD password retrieved"
        break
      fi
    fi

    if [[ $wait_secret -eq 0 ]]; then
      log_warn "Waiting for ArgoCD initial admin secret..."
    fi

    sleep 5
    ((wait_secret+=5))
  done

  if [[ -z "$argo_pass" ]]; then
    log_error "Failed to retrieve ArgoCD password"
    log_error "Check that ArgoCD is properly installed"
    exit 1
  fi

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 9. Save credentials to file
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  local creds_file="$OUTPUTS_DIR/argo/argocd-credentials-${environment}.txt"

  log_info "Saving credentials to: $creds_file"

  cat > "$creds_file" <<EOF
# ArgoCD Credentials - $environment
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

ARGO_HOST=$argo_host
ARGO_USERNAME=$argo_username
ARGO_PASS=$argo_pass

# Access ArgoCD UI:
https://$argo_host

# Login with ArgoCD CLI:
argocd login $argo_host --username=admin --password='$argo_pass' --grpc-web --insecure

# Or use kubectl port-forward:
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context $cluster_name
# Then access: https://localhost:8080
EOF

  log_success "✓ Credentials saved to: $creds_file"

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 10. Display credentials
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  log_info "========================================="
  log_success "✓ Connection Complete!"
  log_info "========================================="
  echo ""
  echo "ArgoCD Server Details:"
  echo "---------------------"
  echo "Host:     $argo_host"
  echo "Username: $argo_username"
  echo "Password: $argo_pass"
  echo ""
  echo "Access ArgoCD UI:"
  echo "  https://$argo_host"
  echo ""
  echo "Kubectl context:"
  echo "  kubectl config use-context $cluster_name"
  echo ""
  echo "Credentials file:"
  echo "  $creds_file"
  echo ""

  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  # 11. Optional: Login with ArgoCD CLI
  #-------------------------------------------------------------------------------------------------------------------------------------------------#
  if command -v argocd >/dev/null 2>&1 && [[ "$argo_host" != "<pending>" ]]; then
    log_info "ArgoCD CLI detected. Attempting to login..."

    if argocd login "$argo_host" \
      --username="$argo_username" \
      --password="$argo_pass" \
      --grpc-web \
      --insecure \
      --skip-test-tls 2>&1 | tee -a "$LOG_FILE"; then
      log_success "✓ ArgoCD CLI login successful"
    else
      log_warn "ArgoCD CLI login failed (LoadBalancer may not be ready yet)"
      log_info "You can login manually later with:"
      log_info "  argocd login $argo_host --username=admin --password='$argo_pass' --grpc-web --insecure"
    fi
  else
    if [[ "$argo_host" == "<pending>" ]]; then
      log_info "LoadBalancer not ready. Login with ArgoCD CLI after LoadBalancer is provisioned."
    else
      log_info "ArgoCD CLI not found. Install it to enable CLI access:"
      log_info "  https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    fi
  fi

  log_info "========================================="
  log_success "✓ Script completed successfully"
  log_info "Log file: $LOG_FILE"
  log_info "========================================="
}

# Run main function
main "$@"
