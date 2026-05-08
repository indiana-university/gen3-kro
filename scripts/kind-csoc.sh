#!/usr/bin/env bash
###############################################################################
# Kind Local CSOC — Flag-based Orchestration for gen3-kro
#
# gen3-kro is a LOCAL CSOC: a Kind cluster on the developer's laptop that
# manages REAL AWS resources via ACK controllers + KRO, mirroring how
# gen3-kro's CSOC EKS cluster manages spoke accounts.
#
# Mirrors gen3-kro's container-init.sh pattern. Each stage is opt-in via
# positional flags. With no flags, nothing runs (safe no-op).
#
# Usage:
#   bash scripts/kind-csoc.sh                          # No-op
#   bash scripts/kind-csoc.sh create                   # Kind cluster only
#   bash scripts/kind-csoc.sh create install           # Cluster + full stack (auto-injects creds)
#   bash scripts/kind-csoc.sh create install connect   # Full pipeline
#   bash scripts/kind-csoc.sh connect                  # Reconnect ArgoCD
#   bash scripts/kind-csoc.sh inject-creds             # Refresh ACK creds (also auto-runs in install)
#   bash scripts/kind-csoc.sh status                   # Show pod status
#   bash scripts/kind-csoc.sh destroy                  # Tear down
#
# Stages:
#   create       — Create Kind cluster + export kubeconfig
#   install      — Install ArgoCD + apply bootstrap ApplicationSets + auto-inject ACK creds
#   inject-creds — Refresh ACK credentials Secret (also auto-runs during install)
#   connect      — Retrieve ArgoCD password + start port-forward
#   test         — Apply test instances + validate RGD reconciliation
#   status       — Show pod/resource status across all namespaces
#   destroy      — Delete Kind cluster
#   setup        — Validate AWS creds + generate config/local.env
#
# Bootstrap pattern (mirrors gen3-kro EKS CSOC):
#   1. kind-csoc.sh installs ArgoCD via Helm (only direct install)
#   2. Creates ArgoCD cluster Secret with fleet_member labels
#   3. Applies bootstrap ApplicationSets (csoc-addons + fleet-instances)
#   4. ArgoCD reconciles everything via application-sets chart:
#      Wave -30: KRO controller
#      Wave   1: ACK controllers (from addons.yaml, pointed at REAL AWS)
#      Wave  10: KRO ResourceGraphDefinitions
#      Wave  30: KRO instances (from fleet-instances, when uncommented)
#
# KRO instance sync-wave ordering:
#   Wave 14: infrastructure-values ConfigMap
#   Wave 15: Network1  / Wave 16: DNS1, Storage1
#   Wave 20: Compute1, Database1, Search1
#   Wave 24: OIDC1  / Wave 25: AppIAM1, Advanced1, Messaging1
#   Wave 27: ClusterResources1  / Wave 30: Helm1
#
# AWS Credentials:
#   ACK controllers use REAL AWS APIs (no LocalStack).
#   Credentials come from ~/.aws/credentials.
#   AWS_PROFILE=csoc.
#   Run `scripts/mfa-session.sh <MFA_CODE>` on HOST to refresh.
#   install stage auto-injects creds; run $0 inject-creds to refresh later
#
# Fleet instance directory (local Kind):
#   argocd/local-kind/test/
#     infrastructure/     — infra tiers (Network, DNS, Storage, Compute, Database, Search, AppIAM)
#     cluster-resources/  — ClusterResources1
#     applications/       — Helm1
#     tests/              — KRO capability test instances
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUTPUTS_DIR="${REPO_DIR}/outputs"
LOG_DIR="${OUTPUTS_DIR}/logs"
CONFIG_DIR="${REPO_DIR}/config"
ENV_FILE="${CONFIG_DIR}/local.env"

mkdir -p "$LOG_DIR" "$CONFIG_DIR"

# ── Logging helpers (inline — no lib-logging.sh dependency) ─────────────────
if [[ -t 1 ]]; then
  _CLR_RST='\033[0m'; _CLR_GRN='\033[0;32m'; _CLR_YLW='\033[0;33m'
  _CLR_RED='\033[0;31m'; _CLR_BLU='\033[0;34m'; _CLR_CYN='\033[0;36m'
else
  _CLR_RST=''; _CLR_GRN=''; _CLR_YLW=''; _CLR_RED=''; _CLR_BLU=''; _CLR_CYN=''
fi
log_info()    { echo -e "${_CLR_BLU}  ℹ${_CLR_RST} $*"; }
log_success() { echo -e "${_CLR_GRN}  ✓${_CLR_RST} $*"; }
log_warn()    { echo -e "${_CLR_YLW}  ⚠${_CLR_RST} $*" >&2; }
log_error()   { echo -e "${_CLR_RED}  ✗${_CLR_RST} $*" >&2; }
log_stage()   { echo -e "\n${_CLR_CYN}>>> [$1]${_CLR_RST} $2"; }
log_banner()  { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  $*"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

###############################################################################
# Constants — match gen3-kro component versions
###############################################################################
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-gen3-local}"
KIND_CONTEXT="kind-${KIND_CLUSTER_NAME}"
KIND_CONFIG="${SCRIPT_DIR}/kind-config.yaml"

# Dedicated kubeconfig (not shared ~/.kube)
GEN3_DEV_DIR="${HOME}/.gen3-dev"
KUBECONFIG_PATH="${KUBECONFIG:-${GEN3_DEV_DIR}/kubeconfig}"

# ArgoCD — the ONLY component installed via direct Helm
ARGOCD_CHART="argo-cd"
ARGOCD_REPO="https://argoproj.github.io/argo-helm"
ARGOCD_VERSION="7.7.16"
ARGOCD_NAMESPACE="argocd"

# Git repository (used in ArgoCD cluster Secret annotations)
GIT_REPO_URL="https://github.com/indiana-university/gen3-kro.git"
GIT_REPO_REVISION="main"
GIT_REPO_BASEPATH="argocd/"

# ACK Controllers — installed by ArgoCD, credentials injected by this script
# NO endpoint_url override — controllers talk to REAL AWS APIs
# Controller list and versions are defined in controller-values base + Kind override.
# This script discovers enabled ACK controllers from the same merged values.
ACK_NAMESPACE="ack"
ADDONS_BASE_YAML="${REPO_DIR}/argocd/csoc/controller-values/values.yaml"
ADDONS_KIND_OVERRIDES_YAML="${REPO_DIR}/argocd/csoc/controller-values/kind-overrides/addons.yaml"
ADDONS_APPSET_CHART="${REPO_DIR}/argocd/csoc/helm/agrocd-application-sets"
FLEET_DIR="${REPO_DIR}/argocd/local-kind/test"

# AWS credential state (set by validate_credentials)
CRED_TIER="tier4"
CRED_IDENTITY=""
CRED_EXPIRY_UTC=""
CRED_REMAINING_S="-1"
CRED_REPORT_FILE="${OUTPUTS_DIR}/credential-report.txt"

###############################################################################
# Parse flags into associative array (same pattern as gen3-kro container-init)
###############################################################################
declare -A STAGES=()
for arg in "$@"; do
  STAGES["$arg"]=1
done

if [[ ${#STAGES[@]} -eq 0 ]]; then
  echo "Usage: bash $0 <create|install|inject-creds|connect|test|status|destroy|setup>"
  echo "  Stages can be combined: bash $0 create install inject-creds connect"
  exit 0
fi

###############################################################################
# Credential validation (adapted from gen3-kro's container-init.sh)
###############################################################################
validate_credentials() {
  local creds_file="${HOME}/.aws/credentials"
  local meta_file="${HOME}/.aws/.session-meta"
  local profile="${AWS_PROFILE:-csoc}"

  echo "  ── Credential Security Check ──"
  echo ""

  # Tier 4: No credentials file
  if [[ ! -f "$creds_file" ]]; then
    CRED_TIER="tier4"
    log_error "TIER 4 — NO CREDENTIALS"
    log_info "~/.aws/credentials not found."
    log_info "Run on HOST: bash scripts/mfa-session.sh <MFA_CODE>"
    _write_credential_report
    return 1
  fi

  log_success "Credentials file found: ${creds_file}"

  # Read session metadata if available
  local meta_type="" meta_expiry="" meta_duration=""
  if [[ -f "$meta_file" ]]; then
    meta_type="$(grep '^CREDENTIAL_TYPE=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    meta_expiry="$(grep '^EXPIRY=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    meta_duration="$(grep '^DURATION_SECONDS=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    log_success "Session metadata found (type: ${meta_type:-unknown})"
  else
    log_warn "No session metadata — will detect credential type via STS"
  fi

  # Check for session token
  local has_session_token=false
  if grep -A10 "^\[${profile}\]" "$creds_file" 2>/dev/null | grep -q "aws_session_token"; then
    has_session_token=true
  fi

  # Validate via STS
  log_info "Validating credentials (profile: ${profile})..."
  if ! aws sts get-caller-identity --profile "$profile" &>/dev/null; then
    CRED_TIER="tier3"
    log_error "TIER 3 — CREDENTIALS INVALID OR EXPIRED"
    if [[ "$has_session_token" == true ]]; then
      log_info "Session token present but STS validation failed (likely expired)."
    else
      log_info "Static credentials present but STS validation failed."
    fi
    log_info "Renew on HOST: bash scripts/mfa-session.sh <MFA_CODE>"
    _write_credential_report
    return 1
  fi

  CRED_IDENTITY="$(aws sts get-caller-identity --profile "$profile" --output text --query 'Arn' 2>/dev/null || echo 'unknown')"
  log_success "STS validation passed: ${CRED_IDENTITY}"

  # Tier 1: MFA assumed-role
  if { [[ "$has_session_token" == true ]] && echo "$CRED_IDENTITY" | grep -q "assumed-role"; } \
     || [[ "$meta_type" == "assumed-role" ]]; then
    CRED_TIER="tier1"
    log_success "TIER 1 — MFA ASSUMED-ROLE (most secure)"
    _check_expiry "$meta_expiry" "$meta_duration"
    if [[ "$CRED_REMAINING_S" -gt 0 && "$CRED_REMAINING_S" -lt 3600 ]]; then
      log_warn "Credentials expire in less than 1 hour! ($(( CRED_REMAINING_S / 60 ))m remaining)"
      log_info "Renew on HOST: bash scripts/mfa-session.sh <MFA_CODE>"
    elif [[ "$CRED_REMAINING_S" -gt 0 ]]; then
      log_info "Remaining: $(( CRED_REMAINING_S / 3600 ))h $(( (CRED_REMAINING_S % 3600) / 60 ))m"
    fi
    _write_credential_report
    return 0
  fi

  # Tier 2: Static IAM user
  if [[ "$has_session_token" == false ]] || [[ "$meta_type" == "static" ]]; then
    CRED_TIER="tier2"
    log_warn "TIER 2 — STATIC IAM USER CREDENTIALS (less secure)"
    log_info "Upgrade to Tier 1: bash scripts/mfa-session.sh <MFA_CODE>"
    _write_credential_report
    return 0
  fi

  # Fallback
  if echo "$CRED_IDENTITY" | grep -q "assumed-role"; then
    CRED_TIER="tier1"
    log_success "TIER 1 — ASSUMED-ROLE (detected via STS)"
    _write_credential_report
    return 0
  fi

  CRED_TIER="tier2"
  log_warn "TIER 2 — UNCLASSIFIED CREDENTIALS"
  _write_credential_report
  return 0
}

_check_expiry() {
  local meta_expiry="$1" meta_duration="$2"
  if [[ -n "$meta_expiry" && "$meta_expiry" != "(static credentials"* ]]; then
    CRED_EXPIRY_UTC="$meta_expiry"
    local expiry_epoch now_epoch
    expiry_epoch="$(date -d "$meta_expiry" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if [[ "$expiry_epoch" -gt 0 ]]; then
      CRED_REMAINING_S=$(( expiry_epoch - now_epoch ))
      log_info "Expiry: ${CRED_EXPIRY_UTC}"
      return 0
    fi
  fi
  local meta_file="${HOME}/.aws/.session-meta"
  if [[ -f "$meta_file" && -n "$meta_duration" ]]; then
    local created_at
    created_at="$(grep '^CREATED_AT=' "$meta_file" 2>/dev/null | cut -d= -f2 || true)"
    if [[ -n "$created_at" ]]; then
      local created_epoch now_epoch
      created_epoch="$(date -d "$created_at" +%s 2>/dev/null || echo 0)"
      now_epoch="$(date +%s)"
      if [[ "$created_epoch" -gt 0 ]]; then
        local expiry_epoch=$(( created_epoch + meta_duration ))
        CRED_REMAINING_S=$(( expiry_epoch - now_epoch ))
        CRED_EXPIRY_UTC="$(date -u -d "@${expiry_epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
        log_info "Expiry: ${CRED_EXPIRY_UTC} (computed from session metadata)"
        return 0
      fi
    fi
  fi
  CRED_REMAINING_S="-1"
}

_write_credential_report() {
  local tier_label=""
  case "$CRED_TIER" in
    tier1) tier_label="TIER 1 — MFA Assumed-Role (most secure)" ;;
    tier2) tier_label="TIER 2 — Static IAM User (less secure)" ;;
    tier3) tier_label="TIER 3 — Invalid or Expired" ;;
    tier4) tier_label="TIER 4 — No Credentials" ;;
  esac
  cat > "$CRED_REPORT_FILE" <<REPORT
# Credential Security Report — $(date -u +%Y-%m-%dT%H:%M:%SZ)
TIER:          ${CRED_TIER}
STATUS:        ${tier_label}
IDENTITY:      ${CRED_IDENTITY:-none}
EXPIRY:        ${CRED_EXPIRY_UTC:-N/A}
REMAINING_SEC: ${CRED_REMAINING_S}
REPORT
  log_info "Report written to: ${CRED_REPORT_FILE}"
}

_require_valid_credentials() {
  local stage="$1"
  if [[ "$CRED_TIER" == "tier3" || "$CRED_TIER" == "tier4" ]]; then
    log_error "STAGE BLOCKED: ${stage} — credentials are unusable (${CRED_TIER})"
    log_info "Fix on HOST: bash scripts/mfa-session.sh <MFA_CODE>"
    return 1
  fi
  return 0
}

###############################################################################
# STAGE: setup — Validate credentials + generate config/local.env
###############################################################################
stage_setup() {
  log_stage "setup" "Validating AWS credentials and generating config..."

  validate_credentials || true

  cat > "$ENV_FILE" <<EOF
# gen3-kro local CSOC environment — generated $(date -Iseconds)
# DO NOT COMMIT — listed in .gitignore
export KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME}"
export KIND_CONTEXT="${KIND_CONTEXT}"
export KUBECONFIG="${KUBECONFIG_PATH}"
export REPO_DIR="${REPO_DIR}"
export AWS_PROFILE="${AWS_PROFILE:-csoc}"
export AWS_DEFAULT_REGION="us-east-1"
export CRED_TIER="${CRED_TIER}"
EOF

  log_success "Config written to: ${ENV_FILE}"
}

###############################################################################
# STAGE: create — Create Kind cluster + export kubeconfig
###############################################################################
stage_create() {
  log_stage "create" "Creating Kind cluster: ${KIND_CLUSTER_NAME}..."

  if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    log_warn "Cluster '${KIND_CLUSTER_NAME}' already exists. Delete first with: $0 destroy"
    log_info "Skipping cluster creation."
  else
    if [[ -f "$KIND_CONFIG" ]]; then
      kind create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG"
    else
      log_warn "Kind config not found at ${KIND_CONFIG} — using defaults"
      kind create cluster --name "$KIND_CLUSTER_NAME"
    fi
  fi

  # Export kubeconfig to dedicated path (not shared ~/.kube)
  mkdir -p "$GEN3_DEV_DIR"
  kind export kubeconfig --name "$KIND_CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH"
  log_success "Kubeconfig exported to: ${KUBECONFIG_PATH}"

  # For devcontainer access: replace 127.0.0.1 with host.docker.internal
  # Only apply when running inside a Docker container (e.g. devcontainer).
  # When running on the host or WSL, keep 127.0.0.1 as-is.
  if [[ -f "$KUBECONFIG_PATH" ]] && [[ -f /.dockerenv ]]; then
    sed -i 's|server: https://127\.0\.0\.1:|server: https://host.docker.internal:|g' "$KUBECONFIG_PATH" 2>/dev/null || true
    sed -i 's|server: https://0\.0\.0\.0:|server: https://host.docker.internal:|g' "$KUBECONFIG_PATH" 2>/dev/null || true
    log_info "Kubeconfig server updated for Docker Desktop access"
  fi

  export KUBECONFIG="$KUBECONFIG_PATH"

  if kubectl cluster-info --context "$KIND_CONTEXT" > /dev/null 2>&1; then
    log_success "Kind cluster '${KIND_CLUSTER_NAME}' is running"
    kubectl get nodes --context "$KIND_CONTEXT"
  else
    log_error "Cluster created but not reachable via context '${KIND_CONTEXT}'"
    return 1
  fi
}

###############################################################################
# STAGE: inject-creds — Create/update ACK credentials Secret from AWS creds
#
# Kind has no OIDC provider, so IRSA (used by gen3-kro) is not available.
# Instead, we read the mounted AWS credentials and inject them as a
# Kubernetes Secret, then patch ACK controller Deployments to use it.
#
# Must be re-run when credentials are refreshed (after mfa-session.sh).
###############################################################################
stage_inject_creds() {
  log_stage "inject-creds" "Injecting AWS credentials into ACK controllers..."

  validate_credentials || true
  if ! _require_valid_credentials "inject-creds"; then
    return 1
  fi

  local profile="${AWS_PROFILE:-csoc}"
  local creds_file="${HOME}/.aws/credentials"

  # Extract credentials from the mounted file
  local ak sk st
  ak="$(aws configure get aws_access_key_id --profile "$profile" 2>/dev/null || true)"
  sk="$(aws configure get aws_secret_access_key --profile "$profile" 2>/dev/null || true)"
  st="$(aws configure get aws_session_token --profile "$profile" 2>/dev/null || true)"

  if [[ -z "$ak" ]] || [[ -z "$sk" ]]; then
    log_error "Could not read credentials from profile '${profile}'"
    return 1
  fi

  # Create/update the credentials Secret in ACK namespace
  kubectl create namespace "$ACK_NAMESPACE" --context "$KIND_CONTEXT" 2>/dev/null || true

  local secret_data="AWS_ACCESS_KEY_ID=${ak}
AWS_SECRET_ACCESS_KEY=${sk}
AWS_DEFAULT_REGION=us-east-1"

  # Include session token if present (Tier 1 MFA credentials)
  if [[ -n "$st" ]]; then
    secret_data="${secret_data}
AWS_SESSION_TOKEN=${st}"
  fi

  kubectl apply --context "$KIND_CONTEXT" -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: ack-aws-credentials
  namespace: ${ACK_NAMESPACE}
type: Opaque
stringData:
$(echo "$secret_data" | while IFS='=' read -r key val; do
    echo "  ${key}: \"${val}\""
  done)
YAML
  log_success "ACK credentials Secret created/updated in ${ACK_NAMESPACE}"

  # Wait for ACK deployments to exist before patching (ArgoCD creates them async)
  # Expected count is derived from the same base+Kind override values ArgoCD renders.
  log_info "Waiting for ACK controller deployments to be created by ArgoCD..."
  local max_deploy_wait=300
  local deploy_elapsed=0
  local expected_count
  expected_count=""
  if command -v helm >/dev/null 2>&1 && [[ -d "${ADDONS_APPSET_CHART}" ]]; then
    expected_count="$(
      helm template csoc-addons "${ADDONS_APPSET_CHART}" \
        -f "${ADDONS_BASE_YAML}" \
        -f "${ADDONS_KIND_OVERRIDES_YAML}" 2>/dev/null \
        | awk '
            /^kind: ApplicationSet$/ { in_appset = 1; next }
            in_appset && /^  name: ack-/ { count++; in_appset = 0 }
            /^---$/ { in_appset = 0 }
            END { print count + 0 }
          '
    )"
  fi
  if [[ ! "${expected_count}" =~ ^[0-9]+$ ]]; then
    if command -v yq >/dev/null 2>&1; then
      expected_count="$(
        yq eval-all '. as $item ireduce ({}; . * $item) | to_entries | map(select((.key | test("^ack-")) and (.value.enabled == true))) | length' \
          "${ADDONS_BASE_YAML}" "${ADDONS_KIND_OVERRIDES_YAML}" 2>/dev/null || true
      )"
    fi
  fi
  if [[ ! "${expected_count}" =~ ^[0-9]+$ ]]; then
    expected_count="$(
      awk '
        /^ack-/ { in_ack = 1; enabled = 0; next }
        /^[^[:space:]].*:/ {
          if (in_ack && enabled == 1) count++
          in_ack = 0
          enabled = 0
        }
        in_ack && /^[[:space:]]+enabled:[[:space:]]+true([[:space:]]|$)/ { enabled = 1 }
        END {
          if (in_ack && enabled == 1) count++
          print count + 0
        }
      ' "${ADDONS_KIND_OVERRIDES_YAML}" 2>/dev/null
    )"
  fi
  log_info "Expected ACK controllers (from Kind controller values): ${expected_count}"
  while true; do
    local found_count
    found_count=$(kubectl get deployments -n "$ACK_NAMESPACE" --context "$KIND_CONTEXT" \
      --no-headers 2>/dev/null | wc -l || echo 0)
    if [[ "$found_count" -ge "$expected_count" ]]; then
      log_success "All ${expected_count} ACK controller deployments found"
      break
    fi
    if [[ $deploy_elapsed -ge $max_deploy_wait ]]; then
      log_warn "Only ${found_count}/${expected_count} ACK deployments found after ${max_deploy_wait}s — proceeding with available"
      break
    fi
    sleep 10
    deploy_elapsed=$((deploy_elapsed + 10))
    log_info "  ${found_count}/${expected_count} ACK deployments found (${deploy_elapsed}s)"
  done

  # Inject credentials into ACK deployments — all deployments in the ack namespace
  # are controllers rendered from the Kind controller-values override.
  local deployments
  deployments=$(kubectl get deployments -n "$ACK_NAMESPACE" --context "$KIND_CONTEXT" \
    --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  if [[ -z "$deployments" ]]; then
    log_warn "No ACK deployments found in ${ACK_NAMESPACE} — nothing to inject"
  else
    while IFS= read -r deploy; do
      [[ -z "$deploy" ]] && continue
      # Clear any chart-default file-based credential env vars (e.g. opensearchservice)
      # so the controller falls back to env var credentials from the Secret.
      kubectl set env deployment/"$deploy" \
        AWS_SHARED_CREDENTIALS_FILE- \
        AWS_PROFILE- \
        -n "$ACK_NAMESPACE" \
        --context "$KIND_CONTEXT" 2>/dev/null || true

      kubectl set env deployment/"$deploy" \
        --from=secret/ack-aws-credentials \
        -n "$ACK_NAMESPACE" \
        --context "$KIND_CONTEXT" 2>/dev/null && \
        log_success "Credentials injected into ${deploy}" || \
        log_warn "Could not inject credentials into ${deploy}"
    done <<< "$deployments"
  fi

  # ── Update AWS Account ID on ArgoCD cluster Secret and spoke Namespaces ──
  # The install stage sets aws_account_id on the cluster Secret initially.
  # On credential renewal the STS identity may differ, so we update both
  # the cluster Secret annotation AND all spoke Namespaces directly.
  # (The directory source ApplicationSet applies raw CR YAML directly.)
  log_banner "Updating AWS Account ID on ArgoCD cluster Secret and spoke Namespaces"
  local aws_account_id
  aws_account_id="$(aws sts get-caller-identity --profile "${profile}" --output text --query 'Account' 2>/dev/null || true)"
  if [[ -z "${aws_account_id}" ]]; then
    log_error "Could not resolve AWS Account ID — RGDs will fail without it"
    return 1
  fi

  log_info "AWS Account ID: ${aws_account_id}"
  kubectl annotate secret local-aws-dev \
    -n "${ARGOCD_NAMESPACE}" \
    --context "${KIND_CONTEXT}" \
    "aws_account_id=${aws_account_id}" \
    --overwrite 2>/dev/null && \
    log_success "ArgoCD cluster Secret updated with account ID" || \
    log_warn "Could not update ArgoCD cluster Secret — install stage may not have run yet"

  # Annotate spoke Namespaces with account ID (used by ACK controllers)
  create_spoke_namespaces "${aws_account_id}"
}

###############################################################################
# HELPER: discover_spoke_namespaces — Extract namespaces from fleet instance YAMLs
#
# Scans local-kind/test/{infrastructure,cluster-resources,applications,tests}/*.yaml
# for metadata.namespace values. Handles both active and commented-out instances
# so namespaces are pre-created before instances are uncommented.
# YAML files in local-kind/test/ are the single source of truth.
###############################################################################
discover_spoke_namespaces() {
  local namespaces=()
  for dir in infrastructure cluster-resources applications tests; do
    local scan_dir="${FLEET_DIR}/${dir}"
    [[ -d "$scan_dir" ]] || continue
    # Match '  namespace: <value>' lines (active or commented-out).
    # Anchored to start-of-line so camelCase fields like
    # foundationNamespace/computeNamespace/producerNamespace are excluded
    # (they don't start with 'namespace:' after stripping comments/whitespace).
    while IFS= read -r ns; do
      [[ -n "$ns" ]] && namespaces+=("$ns")
    done < <(
      grep -rh '^\s*#*\s*namespace:' "$scan_dir"/*.yaml 2>/dev/null \
        | sed 's/^[# ]*//' \
        | sed 's/namespace:\s*//' \
        | tr -d '"' | tr -d "'" | tr -d ' ' \
        | grep -v '^$' \
        | sort -u
    )
  done
  # Output unique, sorted list
  printf '%s\n' "${namespaces[@]}" | sort -u
}

###############################################################################
# HELPER: create_spoke_namespaces — Create spoke Namespaces with ACK annotation
#
# Creates all KRO instance namespaces with services.k8s.aws/owner-account-id,
# required by ACK controllers to route API calls to the correct AWS account.
# Namespace list is discovered from fleet instance YAMLs (not hardcoded).
# Called by stage_install (initial setup) and stage_inject_creds (cred renewal).
###############################################################################
create_spoke_namespaces() {
  local aws_account_id="$1"
  if [[ -z "${aws_account_id}" ]]; then
    log_warn "No AWS account ID provided — spoke Namespaces will not be annotated"
    return 0
  fi
  log_banner "Creating/updating spoke Namespaces with AWS account ID annotation"

  local discovered_namespaces
  discovered_namespaces=$(discover_spoke_namespaces)
  if [[ -z "$discovered_namespaces" ]]; then
    log_warn "No namespaces found in fleet instance YAMLs — nothing to create"
    return 0
  fi

  local ns_count
  ns_count=$(echo "$discovered_namespaces" | wc -l)
  log_info "Discovered ${ns_count} namespaces from fleet instance YAMLs"

  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue

    kubectl apply --context "$KIND_CONTEXT" -f - <<NSYAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
  annotations:
    services.k8s.aws/owner-account-id: "${aws_account_id}"
NSYAML
    log_success "Namespace '${ns}' created/annotated with owner-account-id"
  done <<< "$discovered_namespaces"
}

###############################################################################
# STAGE: install — Bootstrap cluster via ArgoCD (mirrors gen3-kro pattern)
#
# ArgoCD is the ONLY component installed directly via Helm.
# Everything else (KRO, ACK controllers, RGDs, instances) is deployed
# by ArgoCD through the bootstrap ApplicationSet chain:
#   1. Install ArgoCD via Helm
#   2. Create ArgoCD cluster Secret (enables cluster generator matching)
#   3. Apply bootstrap ApplicationSets (csoc-addons + local-infra-instances)
#   4. ArgoCD reconciles: application-sets chart → per-addon ApplicationSets
###############################################################################
stage_install() {
  log_stage "install" "Bootstrapping cluster via ArgoCD..."

  validate_credentials || true
  if ! _require_valid_credentials "install"; then
    return 1
  fi

  export KUBECONFIG="$KUBECONFIG_PATH"
  local ctx="--kube-context=${KIND_CONTEXT}"

  # ── ArgoCD (the ONLY direct Helm install) ─────────────────────────────
  log_banner "Installing ArgoCD (the only Helm-managed component)"
  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update argo 2>/dev/null || true

  helm upgrade --install argocd "$ARGOCD_CHART" \
    --repo "$ARGOCD_REPO" \
    --namespace "$ARGOCD_NAMESPACE" \
    --create-namespace \
    --version "$ARGOCD_VERSION" \
    --set server.service.type=NodePort \
    --set server.service.nodePort=30080 \
    --set "configs.params.server\\.insecure=true" \
    --set dex.enabled=false \
    --set notifications.enabled=false \
    $ctx \
    --wait --timeout 5m
  log_success "ArgoCD v${ARGOCD_VERSION} installed in ${ARGOCD_NAMESPACE}"
  wait_for_pods "$ARGOCD_NAMESPACE" 180

  # ── ArgoCD Cluster Secret (enables cluster generator matching) ────────
  log_banner "Creating ArgoCD Cluster Secret"

  # Fetch AWS account ID at runtime (never stored in git)
  local aws_account_id
  aws_account_id="$(aws sts get-caller-identity --profile "${AWS_PROFILE:-csoc}" --output text --query 'Account' 2>/dev/null || true)"
  if [[ -z "${aws_account_id}" ]]; then
    log_warn "Could not determine AWS account ID — cluster secret will lack aws_account_id annotation"
  else
    log_success "AWS Account ID resolved at runtime: ${aws_account_id}"
  fi

  kubectl apply --context "$KIND_CONTEXT" -f - <<CLUSTERSECRET
apiVersion: v1
kind: Secret
metadata:
  name: local-aws-dev
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: cluster
    fleet_member: control-plane
    ack_management_mode: self_managed
    cluster_type: kind
    enable_infra_instances: "true"
    enable_kro_csoc_rgs: "true"
    enable_external_secrets: "true"
  annotations:
    addons_repo_url: "${GIT_REPO_URL}"
    addons_repo_revision: "${GIT_REPO_REVISION}"
    addons_repo_basepath: "${GIT_REPO_BASEPATH}"
    fleet_repo_url: "${GIT_REPO_URL}"
    fleet_repo_revision: "${GIT_REPO_REVISION}"
    fleet_repo_basepath: "${GIT_REPO_BASEPATH}"
    fleet_instances_path: "local-kind/test"
    aws_region: "us-east-1"
    aws_account_id: "${aws_account_id}"
type: Opaque
stringData:
  name: local-aws-dev
  server: https://kubernetes.default.svc
  config: |
    {
      "tlsClientConfig": {
        "insecure": true
      }
    }
CLUSTERSECRET
  log_success "ArgoCD cluster Secret 'local-aws-dev' created (fleet_member=control-plane)"

  # Annotate spoke Namespaces with account ID (ACK requires this for API routing)
  create_spoke_namespaces "${aws_account_id}"

  # ── OCI Helm Repository Secrets ───────────────────────────────────────
  # ArgoCD needs these to recognize OCI registries for KRO and ACK charts.
  # The URL must NOT include the oci:// prefix (ArgoCD adds it internally).
  log_banner "Creating OCI Helm Repository Secrets"
  for name_url in "kro-oci-repo registry.k8s.io/kro/charts" "ack-oci-repo public.ecr.aws/aws-controllers-k8s"; do
    read -r sec_name sec_url <<< "${name_url}"
    kubectl apply --context "$KIND_CONTEXT" -f - <<OCISECRET
apiVersion: v1
kind: Secret
metadata:
  name: ${sec_name}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: helm
  name: ${sec_name}
  url: ${sec_url}
  enableOCI: "true"
OCISECRET
    log_success "OCI repo '${sec_name}' → ${sec_url}"
  done

  # ── Bootstrap ApplicationSets ─────────────────────────────────────────
  log_banner "Applying Bootstrap ApplicationSets"
  local bootstrap_dir="${REPO_DIR}/argocd/bootstrap"

  for manifest in csoc-addons.yaml fleet-instances.yaml; do
    local manifest_path="${bootstrap_dir}/${manifest}"
    if [[ -f "$manifest_path" ]]; then
      log_info "Applying: ${manifest}"
      kubectl apply -f "$manifest_path" --context "$KIND_CONTEXT" 2>/dev/null || \
        log_warn "No active objects in ${manifest} (file may be fully commented-out — skipped)"
    else
      log_warn "Bootstrap manifest not found: ${manifest_path}"
    fi
  done
  log_success "Bootstrap ApplicationSets applied"

  # ── Wait for ArgoCD to begin reconciling ──────────────────────────────
  log_banner "Waiting for ArgoCD to reconcile components..."
  log_info "ArgoCD will deploy: KRO (wave -30) → ACK controllers (wave 1) → RGDs (wave 10) → fleet instances (wave 30)"
  log_info "Monitor: kubectl get applications -n argocd --context ${KIND_CONTEXT}"

  # ── Auto-inject ACK credentials ────────────────────────────────────────
  # ArgoCD is now deploying ACK controllers asynchronously.  Inject creds
  # automatically so ACK pods start with valid credentials and avoid an
  # initial CrashLoopBackOff cycle.  Skipped only if inject-creds is also
  # an explicit stage (the user wants manual control).
  if [[ -z "${STAGES[inject-creds]:-}" ]]; then
    log_info "Auto-injecting ACK credentials (part of install)..."
    stage_inject_creds
  fi

  log_banner "INSTALL COMPLETE — Bootstrap applied, credentials injected"
  echo ""
  log_info "ArgoCD Applications:"
  kubectl get applications -n "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" 2>/dev/null || true
  echo ""
  log_info "ArgoCD is reconciling the bootstrap ApplicationSets."
  log_info "KRO (wave -30) → ACK controllers (wave 1) → RGDs (wave 10) will deploy asynchronously."
  log_info "Monitor: kubectl get applications -n argocd --context ${KIND_CONTEXT}"
}

###############################################################################
# STAGE: connect — ArgoCD password + port-forward (mirrors gen3-kro connect)
###############################################################################
stage_connect() {
  log_stage "connect" "Connecting to ArgoCD in Kind cluster..."

  export KUBECONFIG="$KUBECONFIG_PATH"

  if ! kubectl cluster-info --context "$KIND_CONTEXT" > /dev/null 2>&1; then
    log_error "Cluster '${KIND_CLUSTER_NAME}' not reachable. Run: $0 create"
    return 1
  fi
  log_success "Connected to cluster ${KIND_CLUSTER_NAME}"

  # Retrieve ArgoCD admin password
  local argocd_password=""
  for i in 1 2 3; do
    argocd_password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" --context "$KIND_CONTEXT" 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -n "$argocd_password" ]]; then
      break
    fi
    log_info "Waiting for argocd-initial-admin-secret... (attempt $i/3)"
    sleep 5
  done

  if [[ -n "$argocd_password" ]]; then
    log_success "ArgoCD admin password retrieved"
    if [[ -f "$ENV_FILE" ]]; then
      sed -i '/^export ARGOCD_ADMIN_PASSWORD=/d' "$ENV_FILE" 2>/dev/null || true
      echo "export ARGOCD_ADMIN_PASSWORD=\"${argocd_password}\"" >> "$ENV_FILE"
    fi
    export ARGOCD_ADMIN_PASSWORD="$argocd_password"
  else
    log_warn "ArgoCD password not yet available (ArgoCD may still be deploying)"
  fi

  # Start port-forward (background)
  if command -v lsof &>/dev/null && lsof -ti:8080 >/dev/null 2>&1; then
    kill "$(lsof -ti:8080)" 2>/dev/null || true
    sleep 1
  fi

  local pf_log="${OUTPUTS_DIR}/port-forward.log"
  nohup kubectl port-forward -n "$ARGOCD_NAMESPACE" svc/argocd-server 8080:80 \
    --address 0.0.0.0 \
    --context "$KIND_CONTEXT" > "$pf_log" 2>&1 &
  local pf_pid=$!
  disown "$pf_pid"
  sleep 2

  if kill -0 "$pf_pid" 2>/dev/null; then
    log_banner "ArgoCD Access"
    echo "  URL:       http://localhost:8080"
    echo "  Username:  admin"
    if [[ -n "${argocd_password:-}" ]]; then
      echo "  Password:  ${argocd_password}"
    else
      echo "  Password:  (not yet available — ArgoCD may still be deploying)"
    fi
    echo "  Port-fwd:  kubectl port-forward -n argocd svc/argocd-server 8080:80 --address 0.0.0.0 --context ${KIND_CONTEXT}"
    echo ""
  else
    log_error "Port-forward failed to start (see ${pf_log})"
  fi
}

###############################################################################
# STAGE: test — Apply test instances + validate
###############################################################################
stage_test() {
  log_stage "test" "Running RGD validation tests..."

  export KUBECONFIG="$KUBECONFIG_PATH"

  local test_dir="${REPO_DIR}/tests/local"
  local validate_script="${test_dir}/validate-rgd.sh"

  if [[ -x "$validate_script" ]] || [[ -f "$validate_script" ]]; then
    bash "$validate_script" "$KIND_CONTEXT"
  else
    log_warn "Validation script not found at ${validate_script}"
    log_info "Applying test instances manually..."

    for instance_file in "$test_dir"/*-instance.yaml; do
      if [[ -f "$instance_file" ]]; then
        log_info "Applying: $(basename "$instance_file")"
        kubectl apply -f "$instance_file" --context "$KIND_CONTEXT" || \
          log_warn "Failed to apply $(basename "$instance_file")"
      fi
    done

    sleep 10
    log_info "Current KRO instances:"
    kubectl get resourcegraphdefinitions --context "$KIND_CONTEXT" 2>/dev/null || true
  fi
}

###############################################################################
# STAGE: status — Show cluster status
###############################################################################
stage_status() {
  log_stage "status" "Cluster status for '${KIND_CLUSTER_NAME}'..."

  export KUBECONFIG="$KUBECONFIG_PATH"

  if ! kubectl cluster-info --context "$KIND_CONTEXT" > /dev/null 2>&1; then
    log_error "Cluster '${KIND_CLUSTER_NAME}' not reachable"
    return 1
  fi

  echo ""
  log_info "Nodes:"
  kubectl get nodes --context "$KIND_CONTEXT"

  echo ""
  log_info "Pods (all namespaces):"
  kubectl get pods -A --context "$KIND_CONTEXT"

  echo ""
  log_info "ArgoCD Applications:"
  kubectl get applications -n "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" 2>/dev/null || log_info "(none)"

  echo ""
  log_info "ArgoCD ApplicationSets:"
  kubectl get applicationsets -n "$ARGOCD_NAMESPACE" --context "$KIND_CONTEXT" 2>/dev/null || log_info "(none)"

  echo ""
  log_info "KRO ResourceGraphDefinitions:"
  kubectl get resourcegraphdefinitions --context "$KIND_CONTEXT" 2>/dev/null || log_info "(none)"

  echo ""
  log_info "KRO-managed CRDs:"
  kubectl get crd --context "$KIND_CONTEXT" 2>/dev/null | grep -E "\.kro\.run" || log_info "(none)"

  echo ""
  log_info "Helm releases (all namespaces):"
  helm list -A --kube-context "$KIND_CONTEXT"
}

###############################################################################
# STAGE: destroy — Delete Kind cluster
###############################################################################
stage_destroy() {
  log_stage "destroy" "Deleting Kind cluster: ${KIND_CLUSTER_NAME}..."

  if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    kind delete cluster --name "$KIND_CLUSTER_NAME"
    log_success "Cluster '${KIND_CLUSTER_NAME}' deleted"
  else
    log_warn "Cluster '${KIND_CLUSTER_NAME}' does not exist"
  fi

  # Clean up kubeconfig
  if [[ -f "$KUBECONFIG_PATH" ]]; then
    rm -f "$KUBECONFIG_PATH"
    log_info "Removed kubeconfig: ${KUBECONFIG_PATH}"
  fi

  # Clean up port-forward
  if command -v lsof &>/dev/null && lsof -ti:8080 >/dev/null 2>&1; then
    kill "$(lsof -ti:8080)" 2>/dev/null || true
    log_info "Killed lingering port-forward on :8080"
  fi
}

###############################################################################
# Helper: wait_for_pods — wait until all pods in a namespace are Ready
###############################################################################
wait_for_pods() {
  local ns="$1" timeout_s="${2:-120}"
  local elapsed=0
  log_info "Waiting for pods in ${ns} to be ready (timeout: ${timeout_s}s)..."
  while true; do
    local not_ready
    not_ready=$(kubectl get pods -n "$ns" --context "$KIND_CONTEXT" \
      --no-headers 2>/dev/null | grep -vc "Running\|Completed" || true)
    if [[ "${not_ready}" -eq 0 ]]; then
      log_success "All pods in ${ns} are ready"
      return 0
    fi
    if [[ $elapsed -ge $timeout_s ]]; then
      log_warn "Timeout waiting for pods in ${ns} — ${not_ready} pod(s) not ready"
      kubectl get pods -n "$ns" --context "$KIND_CONTEXT" 2>/dev/null || true
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
    log_info "  ${not_ready} pod(s) not ready in ${ns} (${elapsed}s)"
  done
}

###############################################################################
# Main — Dispatch stages in dependency order
###############################################################################
main() {
  log_banner "gen3-kro — Local CSOC"
  echo "  Cluster:     ${KIND_CLUSTER_NAME}"
  echo "  Context:     ${KIND_CONTEXT}"
  echo "  Kubeconfig:  ${KUBECONFIG_PATH}"
  echo "  AWS Profile: ${AWS_PROFILE:-csoc}"
  echo "  Stages:      ${!STAGES[*]}"
  echo ""

  [[ -n "${STAGES[setup]:-}" ]]        && stage_setup
  [[ -n "${STAGES[create]:-}" ]]       && stage_create
  [[ -n "${STAGES[install]:-}" ]]      && stage_install
  [[ -n "${STAGES[inject-creds]:-}" ]] && stage_inject_creds
  [[ -n "${STAGES[connect]:-}" ]]      && stage_connect
  [[ -n "${STAGES[test]:-}" ]]         && stage_test
  [[ -n "${STAGES[status]:-}" ]]       && stage_status
  [[ -n "${STAGES[destroy]:-}" ]]      && stage_destroy

  echo ""
  log_banner "All requested stages complete!"
}

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/kind-local-test-${TIMESTAMP}.log"
main 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
