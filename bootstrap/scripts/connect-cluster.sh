#!/usr/bin/env bash
# bootstrap/scripts/connect-cluster.sh
# Updates kubeconfig to connect to the EKS cluster for a given environment

set -euo pipefail
IFS=$'\n\t'

# Script directory resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

# Source logging library
# shellcheck source=./lib-logging.sh
source "${SCRIPT_DIR}/lib-logging.sh"

# Configuration
CONFIG_DIR="${REPO_ROOT}/config"
LOG_DIR="${REPO_ROOT}/outputs/logs"
ARGO_CREDS_DIR="${REPO_ROOT}/outputs/argo"

# Create directories
mkdir -p "$LOG_DIR"
mkdir -p "$ARGO_CREDS_DIR"

# Set log file
LOG_FILE="${LOG_DIR}/connect-cluster-$(date +%Y%m%d-%H%M%S).log"
export LOG_FILE

# Usage information
usage() {
  cat <<EOF
Usage: $(basename "$0") ENVIRONMENT [OPTIONS]

ENVIRONMENT:
  prod        Production environment
  staging     Staging environment
  dr          Disaster recovery environment

OPTIONS:
  -n, --no-verify      Skip kubectl verification after connecting
  -a, --skip-argocd    Skip ArgoCD connection and credential retrieval
  -v, --verbose        Enable verbose logging
  -h, --help           Show this help message

DESCRIPTION:
  Updates the local kubeconfig to connect to the EKS cluster for the
  specified environment. Uses AWS CLI to retrieve cluster endpoint and
  authentication token.

EXAMPLES:
  # Connect to staging cluster
  $(basename "$0") staging

  # Connect to production with verbose output
  $(basename "$0") prod --verbose

  # Connect without verification
  $(basename "$0") staging --no-verify

REQUIREMENTS:
  - aws CLI configured with appropriate credentials
  - kubectl installed
  - yq or python for YAML parsing
  - Appropriate AWS permissions to describe EKS clusters
  - argocd CLI (optional, for ArgoCD login)

NOTES:
  By default, this script will also retrieve ArgoCD credentials and save
  them to outputs/argo/argocd-credentials-{environment}.txt

EOF
}

# Parse YAML configuration
parse_config() {
  local env="$1"
  local config_file="${CONFIG_DIR}/config.yaml"
  local env_file="${CONFIG_DIR}/environments/${env}.yaml"

  log_info "Parsing configuration for environment: $env"

  # Check if config files exist
  if [[ ! -f "$config_file" ]]; then
    log_error "Base configuration file not found: $config_file"
    return 1
  fi

  if [[ ! -f "$env_file" ]]; then
    log_error "Environment configuration file not found: $env_file"
    return 1
  fi

  # Parse cluster name from environment config first, fall back to base config
  if command -v yq >/dev/null 2>&1; then
    # Try environment-specific config first
    CLUSTER_NAME=$(yq eval '.hub.cluster_name' "$env_file" 2>/dev/null || echo "")

    # Fall back to base config if not in environment config
    if [[ -z "$CLUSTER_NAME" || "$CLUSTER_NAME" == "null" ]]; then
      CLUSTER_NAME=$(yq eval '.hub.cluster_name' "$config_file" 2>/dev/null || echo "")
    fi

    AWS_REGION=$(yq eval '.hub.aws_region' "$env_file" 2>/dev/null || yq eval '.hub.aws_region' "$config_file" 2>/dev/null || echo "us-east-1")
    AWS_PROFILE=$(yq eval '.hub.aws_profile' "$env_file" 2>/dev/null || yq eval '.hub.aws_profile' "$config_file" 2>/dev/null || echo "default")
    HUB_ALIAS=$(yq eval '.hub.alias' "$env_file" 2>/dev/null || yq eval '.hub.alias' "$config_file" 2>/dev/null || echo "")
  elif command -v python3 >/dev/null 2>&1; then
    # Fallback to Python for YAML parsing
    local python_script="
import yaml
import sys

with open('$env_file') as f:
    env_config = yaml.safe_load(f)
with open('$config_file') as f:
    base_config = yaml.safe_load(f)

# Merge configs with environment taking precedence
config = {**base_config.get('hub', {}), **env_config.get('hub', {})}

print(config.get('cluster_name', ''))
print(config.get('aws_region', 'us-east-1'))
print(config.get('aws_profile', 'default'))
print(config.get('alias', ''))
"
    local parsed=$(python3 -c "$python_script")
    CLUSTER_NAME=$(echo "$parsed" | sed -n '1p')
    AWS_REGION=$(echo "$parsed" | sed -n '2p')
    AWS_PROFILE=$(echo "$parsed" | sed -n '3p')
    HUB_ALIAS=$(echo "$parsed" | sed -n '4p')
  else
    log_error "Neither yq nor python3 found for YAML parsing"
    return 1
  fi

  # Validate required values
  if [[ -z "$CLUSTER_NAME" || "$CLUSTER_NAME" == "null" ]]; then
    log_error "Could not determine cluster name from configuration"
    return 1
  fi

  # Build full cluster name with environment suffix
  FULL_CLUSTER_NAME="${CLUSTER_NAME}-${env}"

  log_info "Configuration parsed successfully:"
  log_info "  Cluster Name: $FULL_CLUSTER_NAME"
  log_info "  AWS Region: $AWS_REGION"
  log_info "  AWS Profile: $AWS_PROFILE"
  log_info "  Hub Alias: $HUB_ALIAS"

  export CLUSTER_NAME="$FULL_CLUSTER_NAME"
  export AWS_REGION
  export AWS_PROFILE
  export HUB_ALIAS
}

# Validate AWS credentials
validate_aws_credentials() {
  log_info "Validating AWS credentials for profile: $AWS_PROFILE"

  if ! aws configure list --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    log_error "AWS profile not configured: $AWS_PROFILE"
    log_notice "Run: aws configure --profile $AWS_PROFILE"
    return 1
  fi

  # Try to get caller identity
  if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "AWS credentials invalid or expired for profile: $AWS_PROFILE"
    log_notice "Check your AWS credentials and try again"
    return 1
  fi

  local caller_id
  caller_id=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --output json)
  local account_id
  account_id=$(echo "$caller_id" | jq -r '.Account')
  local user_arn
  user_arn=$(echo "$caller_id" | jq -r '.Arn')

  log_success "✓ AWS credentials validated"
  log_info "  Account ID: $account_id"
  log_info "  User ARN: $user_arn"
}

# Check if cluster exists
verify_cluster_exists() {
  log_info "Verifying EKS cluster exists: $CLUSTER_NAME"

  if ! aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --output json >/dev/null 2>&1; then
    log_error "EKS cluster not found: $CLUSTER_NAME"
    log_notice "Available clusters in region $AWS_REGION:"
    aws eks list-clusters \
      --region "$AWS_REGION" \
      --profile "$AWS_PROFILE" \
      --output json | jq -r '.clusters[]' | while read -r cluster; do
      log_notice "  - $cluster"
    done
    return 1
  fi

  # Get cluster details
  local cluster_info
  cluster_info=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --output json)

  local cluster_status
  cluster_status=$(echo "$cluster_info" | jq -r '.cluster.status')
  local cluster_version
  cluster_version=$(echo "$cluster_info" | jq -r '.cluster.version')
  local cluster_endpoint
  cluster_endpoint=$(echo "$cluster_info" | jq -r '.cluster.endpoint')

  log_success "✓ EKS cluster found"
  log_info "  Status: $cluster_status"
  log_info "  Version: $cluster_version"
  log_info "  Endpoint: $cluster_endpoint"

  if [[ "$cluster_status" != "ACTIVE" ]]; then
    log_warn "Cluster status is not ACTIVE: $cluster_status"
    log_warn "Proceeding anyway, but cluster may not be fully operational"
  fi
}

# Update kubeconfig
update_kubeconfig() {
  log_info "Updating kubeconfig for cluster: $CLUSTER_NAME"

  # Build context name
  local context_name="arn:aws:eks:${AWS_REGION}:$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text):cluster/${CLUSTER_NAME}"

  # Update kubeconfig
  if aws eks update-kubeconfig \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --alias "$CLUSTER_NAME" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "✓ Kubeconfig updated successfully"
    log_info "  Context name: $CLUSTER_NAME"
  else
    log_error "Failed to update kubeconfig"
    return 1
  fi

  # Set current context
  if kubectl config use-context "$CLUSTER_NAME" >/dev/null 2>&1; then
    log_success "✓ Switched to context: $CLUSTER_NAME"
  else
    log_error "Failed to switch context to: $CLUSTER_NAME"
    return 1
  fi
}

# Verify kubectl connectivity
verify_kubectl_connectivity() {
  log_info "Verifying kubectl connectivity..."

  # Try to get cluster info
  if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Failed to connect to cluster with kubectl"
    log_notice "Check your AWS credentials and cluster status"
    return 1
  fi

  # Get cluster version
  local server_version
  server_version=$(kubectl version --short 2>/dev/null | grep "Server Version" || kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion')

  log_success "✓ kubectl connectivity verified"
  log_info "  Server version: $server_version"

  # Get node count
  local node_count
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  log_info "  Nodes: $node_count"

  # Get current namespace
  local current_namespace
  current_namespace=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || echo "default")
  log_info "  Current namespace: $current_namespace"
}

# Get ArgoCD server endpoint
get_argocd_endpoint() {
  log_info "Retrieving ArgoCD server endpoint..."

  # Check if ArgoCD is deployed
  if ! kubectl get namespace argocd >/dev/null 2>&1; then
    log_warn "ArgoCD namespace not found - ArgoCD may not be deployed"
    return 1
  fi

  # Check for LoadBalancer service
  local lb_hostname
  lb_hostname=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

  if [[ -n "$lb_hostname" && "$lb_hostname" != "null" ]]; then
    ARGO_HOST="$lb_hostname"
    log_success "✓ ArgoCD LoadBalancer endpoint found"
    log_info "  Endpoint: $ARGO_HOST"
    export ARGO_HOST
    return 0
  fi

  # Check for LoadBalancer IP
  local lb_ip
  lb_ip=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

  if [[ -n "$lb_ip" && "$lb_ip" != "null" ]]; then
    ARGO_HOST="$lb_ip"
    log_success "✓ ArgoCD LoadBalancer IP found"
    log_info "  Endpoint: $ARGO_HOST"
    export ARGO_HOST
    return 0
  fi

  # Fallback to port-forward option
  log_warn "ArgoCD LoadBalancer not found - you'll need to use port-forward"
  log_notice "Run: kubectl port-forward svc/argocd-server -n argocd 8080:443"
  ARGO_HOST="localhost:8080"
  export ARGO_HOST
  return 2
}

# Get ArgoCD admin password
get_argocd_password() {
  log_info "Retrieving ArgoCD admin password..."

  # Get initial admin password from secret
  local password
  password=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

  if [[ -z "$password" ]]; then
    log_warn "Could not retrieve ArgoCD admin password from secret"
    log_notice "The initial admin secret may have been deleted for security"
    log_notice "You may need to reset the password manually"
    return 1
  fi

  ARGO_PASSWORD="$password"
  export ARGO_PASSWORD
  log_success "✓ ArgoCD admin password retrieved"
  return 0
}

# Save ArgoCD credentials
save_argocd_credentials() {
  local environment="$1"
  local creds_file="${ARGO_CREDS_DIR}/argocd-credentials-${environment}.txt"

  log_info "Saving ArgoCD credentials to: $creds_file"

  # Determine protocol and port based on endpoint
  local protocol="https"
  local port=""
  local ui_url="https://${ARGO_HOST}"

  if [[ "$ARGO_HOST" == "localhost:"* ]]; then
    ui_url="https://${ARGO_HOST}"
  fi

  # Create credentials file
  cat > "$creds_file" <<EOF
# ArgoCD Credentials - ${environment}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

ARGO_HOST=${ARGO_HOST}
ARGO_USERNAME=admin
ARGO_PASS=${ARGO_PASSWORD:-<password-not-available>}

# Access ArgoCD UI:
${ui_url}

# Login with ArgoCD CLI:
argocd login ${ARGO_HOST} --username=admin --password='${ARGO_PASSWORD:-<password>}' --grpc-web --insecure

# Or use kubectl port-forward (if LoadBalancer not available):
kubectl port-forward svc/argocd-server -n argocd 8080:443 --context ${CLUSTER_NAME}
# Then access: https://localhost:8080

# Export as environment variables:
export ARGO_HOST=${ARGO_HOST}
export ARGO_USERNAME=admin
export ARGO_PASSWORD='${ARGO_PASSWORD:-<password>}'

# Kubectl context:
export KUBECONFIG=~/.kube/config
export KUBE_CONTEXT=${CLUSTER_NAME}
EOF

  chmod 600 "$creds_file"
  log_success "✓ ArgoCD credentials saved"
  log_info "  File: $creds_file"
  log_notice "  Credentials file permissions set to 600 (owner read/write only)"
}

# Connect to ArgoCD
connect_argocd() {
  local environment="$1"

  log_info "Connecting to ArgoCD..."

  # Get ArgoCD endpoint
  local endpoint_result=0
  get_argocd_endpoint || endpoint_result=$?

  if [[ $endpoint_result -eq 1 ]]; then
    log_error "Failed to get ArgoCD endpoint - skipping ArgoCD connection"
    return 1
  fi

  # Get ArgoCD password
  if ! get_argocd_password; then
    log_warn "Could not retrieve ArgoCD password"
    log_notice "Saving credentials file with placeholder password"
  fi

  # Save credentials
  save_argocd_credentials "$environment"

  # Try to login with ArgoCD CLI if available
  if command -v argocd >/dev/null 2>&1 && [[ -n "${ARGO_PASSWORD:-}" ]]; then
    log_info "Attempting ArgoCD CLI login..."

    if argocd login "$ARGO_HOST" \
      --username=admin \
      --password="$ARGO_PASSWORD" \
      --grpc-web \
      --insecure 2>&1 | tee -a "$LOG_FILE"; then
      log_success "✓ ArgoCD CLI login successful"
    else
      log_warn "ArgoCD CLI login failed, but credentials were saved"
      log_notice "You can login manually using the saved credentials"
    fi
  else
    if ! command -v argocd >/dev/null 2>&1; then
      log_notice "ArgoCD CLI not installed - skipping CLI login"
      log_notice "Install with: brew install argocd (or see https://argo-cd.readthedocs.io/en/stable/cli_installation/)"
    fi
  fi

  log_success "========================================="
  log_success "✓ ArgoCD Connection Complete"
  log_success "========================================="
  log_info "ArgoCD UI: https://${ARGO_HOST}"
  log_info "Username: admin"
  if [[ -n "${ARGO_PASSWORD:-}" ]]; then
    log_info "Password: ${ARGO_PASSWORD}"
  else
    log_warn "Password: <not available - see credentials file>"
  fi
  log_info "Credentials file: ${ARGO_CREDS_DIR}/argocd-credentials-${environment}.txt"
  log_success "========================================="

  return 0
}

# Main function
main() {
  local VERIFY=true
  local VERBOSE=false
  local CONNECT_ARGOCD=true

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--no-verify)
        VERIFY=false
        shift
        ;;
      -a|--skip-argocd)
        CONNECT_ARGOCD=false
        shift
        ;;
      -v|--verbose)
        VERBOSE=true
        export VERBOSE
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

  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  local environment="$1"

  log_info "========================================="
  log_info "Connect to EKS Cluster - gen3-kro"
  log_info "========================================="
  log_info "Environment: $environment"
  log_info "Log file: $LOG_FILE"
  log_info "========================================="

  # Parse configuration
  parse_config "$environment" || exit 1

  # Validate AWS credentials
  validate_aws_credentials || exit 1

  # Verify cluster exists
  verify_cluster_exists || exit 1

  # Update kubeconfig
  update_kubeconfig || exit 1

  # Verify connectivity
  if [[ "$VERIFY" == "true" ]]; then
    verify_kubectl_connectivity || {
      log_warn "kubectl verification failed, but kubeconfig was updated"
      log_notice "You may need to wait for the cluster to become fully operational"
      exit 0
    }
  fi

  # Connect to ArgoCD if requested
  if [[ "$CONNECT_ARGOCD" == "true" ]]; then
    echo ""
    connect_argocd "$environment" || {
      log_warn "ArgoCD connection failed, but kubectl connection succeeded"
      log_notice "You can try connecting to ArgoCD manually later"
    }
  else
    log_notice "Skipping ArgoCD connection (--skip-argocd specified)"
  fi

  echo ""
  log_success "========================================="
  log_success "✓ Successfully connected to cluster!"
  log_success "========================================="
  log_info "Cluster: $CLUSTER_NAME"
  log_info "Region: $AWS_REGION"
  log_info "Context: $CLUSTER_NAME"
  if [[ "$CONNECT_ARGOCD" == "true" ]]; then
    log_info "ArgoCD Credentials: ${ARGO_CREDS_DIR}/argocd-credentials-${environment}.txt"
  fi
  log_success "========================================="
  log_notice "You can now use kubectl to interact with the cluster"
  log_notice "Example: kubectl get pods -A"
  log_info "Log file: $LOG_FILE"
}

# Run main function
main "$@"
