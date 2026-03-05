#!/usr/bin/env bash
# ============================================================================
# Namespace Infrastructure Report — Per-Spoke Resource Inventory
# ============================================================================
# Usage: ./scripts/namespace-infra-report.sh <namespace>
#
# Produces a comprehensive report of infrastructure resources in a spoke
# namespace, organized by deployment phase and dependency order.
#
# Output: stdout + outputs/namespaced-reports/<namespace>-report.md
# ============================================================================
set -euo pipefail

# ── Colors (disabled for file output, enabled for terminal) ────────────────
if [[ -t 1 ]]; then
  CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
  RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
else
  CYAN=''; GREEN=''; YELLOW=''; RED=''; RESET=''; BOLD=''; DIM=''
fi

header()  { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════${RESET}"; echo -e "${CYAN}${BOLD}  $1${RESET}"; echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${RESET}\n"; }
section() { echo -e "${GREEN}${BOLD}▶ $1${RESET}\n"; }
note()    { echo -e "${DIM}$1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠  $1${RESET}"; }
err()     { echo -e "${RED}✗  $1${RESET}"; }
ok()      { echo -e "${GREEN}✓  $1${RESET}"; }

# ── Argument parsing ───────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <namespace> [--no-save]"
  echo ""
  echo "Example: $0 spoke1"
  echo ""
  echo "Options:"
  echo "  --no-save   Skip saving report to outputs/namespaced-reports/"
  exit 1
fi

NAMESPACE="$1"
SAVE_REPORT=true
[[ "${2:-}" == "--no-save" ]] && SAVE_REPORT=false

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Error: namespace '$NAMESPACE' does not exist"
  exit 1
fi

# ── Report output setup ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$REPO_ROOT/outputs/namespaced-reports"
REPORT_FILE="$REPORT_DIR/${NAMESPACE}-report.ansi"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [[ "$SAVE_REPORT" == true ]]; then
  mkdir -p "$REPORT_DIR"
  # Use a subshell + tee so all output goes to both stdout and file
  exec > >(tee "$REPORT_FILE") 2>&1
fi

# ── Helpers ────────────────────────────────────────────────────────────────
# Count resources of a given type in namespace
kcount() { kubectl get "$1" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' '; }

# ============================================================================
# HEADER
# ============================================================================
echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║  Namespace Infrastructure Report                          ║${RESET}"
echo -e "${CYAN}${BOLD}║  KRO + ACK Resources for: ${YELLOW}$(printf '%-31s' "$NAMESPACE")${CYAN}${BOLD}║${RESET}"
echo -e "${CYAN}${BOLD}║  Generated: ${YELLOW}$(printf '%-44s' "$TIMESTAMP")${CYAN}${BOLD}║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"

# ============================================================================
# PHASE 1: Pre-RGD Resources (ACK CARM, IAMRoleSelector)
# ============================================================================
report_pre_rgd() {
  header "PHASE 1 — PRE-RGD RESOURCES (Cross-Account Setup)"

  section "1.1  IAMRoleSelector (CARM)"
  note "Maps spoke namespace → AWS account IAM role (cluster-scoped)"
  # IAMRoleSelectors are cluster-scoped; filter by namespaceSelector matching this namespace
  SELECTOR_JSON=$(kubectl get iamroleselectors -o json 2>/dev/null)
  if [[ -n "$SELECTOR_JSON" ]]; then
    echo "$SELECTOR_JSON" | jq -r --arg ns "$NAMESPACE" '
      .items[]
      | select(.spec.namespaceSelector.names[]? == $ns)
      | [.metadata.name, (.spec.arn // "<none>"), (.spec.namespaceSelector.names | join(",")), .metadata.creationTimestamp]
      | @tsv' \
      | awk 'BEGIN { printf "%-25s %-55s %-15s %s\n", "NAME", "ROLE_ARN", "NAMESPACES", "AGE" }
             { printf "%-25s %-55s %-15s %s\n", $1, $2, $3, $4 }'
    echo ""
    # Validate the selector targets this namespace
    MATCH_COUNT=$(echo "$SELECTOR_JSON" | jq --arg ns "$NAMESPACE" '[.items[] | select(.spec.namespaceSelector.names[]? == $ns)] | length')
    if [[ "$MATCH_COUNT" -eq 0 ]]; then
      warn "No IAMRoleSelector targets namespace '$NAMESPACE'"
    else
      ok "$MATCH_COUNT IAMRoleSelector(s) target '$NAMESPACE'"
    fi
  else
    warn "No IAMRoleSelectors found in cluster"
  fi

  echo ""
  section "1.2  CARM ConfigMap (ack namespace)"
  note "Account-to-role mapping used by ACK controllers"
  CARM_DATA=$(kubectl get configmap ack-role-account-map -n ack -o json 2>/dev/null || echo "")
  if [[ -n "$CARM_DATA" && "$CARM_DATA" != *"NotFound"* ]]; then
    echo "$CARM_DATA" | jq -r '.data | to_entries[] | "\(.key)\t\(.value)"' \
      | awk 'BEGIN { printf "%-15s %s\n", "ACCOUNT_ID", "ROLE_ARN" }
             { printf "%-15s %s\n", $1, $2 }'
    echo ""
    ok "CARM ConfigMap found in 'ack' namespace"
  else
    warn "No CARM ConfigMap found in 'ack' namespace"
    # Fallback: check ack-system
    if kubectl get configmap ack-role-account-map -n ack-system &>/dev/null; then
      note "  (Found in ack-system namespace instead)"
      kubectl get configmap ack-role-account-map -n ack-system -o yaml 2>/dev/null \
        | grep -A1 "$NAMESPACE:"
    fi
  fi
  echo ""
}

# ============================================================================
# PHASE 2: RGD-Deployed Resources (KRO AwsGen3Infra1Flat outputs)
# ============================================================================
report_rgd_resources() {
  header "PHASE 2 — RGD-DEPLOYED RESOURCES (KRO AwsGen3Infra1Flat)"

  # Find the KRO instance in this namespace
  INSTANCE_NAME=$(kubectl get awsgen3infra1flat -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "$INSTANCE_NAME" ]]; then
    err "No AwsGen3Infra1Flat instance found in namespace $NAMESPACE"
    return
  fi

  section "2.0  KRO Instance Status"
  kubectl get awsgen3infra1flat "$INSTANCE_NAME" -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,RGD_ID:.metadata.labels.kro\.run/resource-graph-definition-id,KRO_VER:.metadata.labels.kro\.run/kro-version,AGE:.metadata.creationTimestamp' 2>/dev/null

  echo ""
  note "Conditions:"
  kubectl get awsgen3infra1flat "$INSTANCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.status.conditions[]? | "  \(if .status == "True" then "✓" else "✗" end)  \(.type): \(.reason) — \(.message // "OK")"'

  echo ""
  note "Spec highlights:"
  kubectl get awsgen3infra1flat "$INSTANCE_NAME" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.spec | "  Region:          \(.region)\n  Environment:     \(.environment)\n  VPC CIDR:        \(.vpcCIDR)\n  EKS Version:     \(.eksVersion)\n  Aurora Engine:   \(.auroraEngine) \(.auroraEngineVersion)\n  Aurora Class:    \(.auroraInstanceClass) x\(.auroraInstanceCount)\n  Adoption Policy: \(.adoptionPolicy)\n  Deletion Policy: \(.deletionPolicy)"'

  echo ""
  note "═══════════════════════════════════════════════════════"
  note "  Resource Layers (dependency order: bottom → top)"
  note "═══════════════════════════════════════════════════════"
  echo ""

  # ── Layer 0: KMS Keys ──────────────────────────────────────────────────
  section "2.1  KMS Keys (Layer 0 — encryption foundation)"
  kubectl get keys.kms.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,KEY_ID:.status.keyID,STATE:.status.keyState,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status,AGE:.metadata.creationTimestamp' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 1: VPC ────────────────────────────────────────────────────────
  section "2.2  VPC (Layer 1 — network foundation)"
  kubectl get vpcs.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,VPC_ID:.status.vpcID,CIDR:.spec.cidrBlocks[0],STATE:.status.state,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 2: Internet Gateway ──────────────────────────────────────────
  section "2.3  Internet Gateway (Layer 2)"
  kubectl get internetgateways.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,IGW_ID:.status.internetGatewayID,ATTACHED:.status.attachments[0].state,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 3: Subnets ───────────────────────────────────────────────────
  section "2.4  Subnets (Layer 3 — public, private, database)"
  kubectl get subnets.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SUBNET_ID:.status.subnetID,AZ:.spec.availabilityZone,CIDR:.spec.cidrBlock,STATE:.status.state,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 4: Elastic IPs ───────────────────────────────────────────────
  section "2.5  Elastic IPs (Layer 4 — for NAT Gateways)"
  kubectl get elasticipaddresses.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ALLOC_ID:.status.allocationID,PUBLIC_IP:.status.publicIP,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 5: NAT Gateways ──────────────────────────────────────────────
  section "2.6  NAT Gateways (Layer 5)"
  kubectl get natgateways.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,NAT_GW_ID:.status.natGatewayID,STATE:.status.state,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 6: Route Tables ──────────────────────────────────────────────
  section "2.7  Route Tables (Layer 6)"
  kubectl get routetables.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,RT_ID:.status.routeTableID,VPC:.spec.vpcID,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 7: Security Groups ───────────────────────────────────────────
  section "2.8  Security Groups (Layer 7 — EKS + Aurora)"
  kubectl get securitygroups.ec2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SG_ID:.status.id,VPC:.spec.vpcID,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 8: IAM Roles ─────────────────────────────────────────────────
  section "2.9  IAM Roles (Layer 8)"
  kubectl get roles.iam.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ROLE_ARN:.status.ackResourceMetadata.arn,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 9: S3 Buckets ────────────────────────────────────────────────
  section "2.10  S3 Buckets (Layer 9)"
  kubectl get buckets.s3.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ARN:.status.ackResourceMetadata.arn,REGION:.status.ackResourceMetadata.region,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 10: DB Subnet Group ──────────────────────────────────────────
  section "2.11  DB Subnet Group (Layer 10)"
  kubectl get dbsubnetgroups.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ARN:.status.ackResourceMetadata.arn,STATUS:.status.subnetGroupStatus,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 11: Aurora Cluster ───────────────────────────────────────────
  section "2.12  Aurora PostgreSQL Cluster (Layer 11)"
  kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ENGINE:.spec.engine,STATUS:.status.status,ENDPOINT:.status.endpoint,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""
  note "  Reader endpoint:"
  kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,READER_ENDPOINT:.status.readerEndpoint' 2>/dev/null \
    || echo "  (none)"
  echo ""

  # ── Layer 12: Aurora Instances ─────────────────────────────────────────
  section "2.13  Aurora DB Instances (Layer 12)"
  kubectl get dbinstances.rds.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,CLASS:.spec.dbInstanceClass,AZ:.status.availabilityZone,STATUS:.status.dbInstanceStatus,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 13: EKS Cluster ──────────────────────────────────────────────
  section "2.14  EKS Cluster (Layer 13)"
  kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,VERSION:.spec.version,STATUS:.status.status,ENDPOINT:.status.endpoint,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 14: EKS Access Entry ─────────────────────────────────────────
  section "2.15  EKS Access Entry (Layer 14)"
  kubectl get accessentries.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PRINCIPAL:.spec.principalARN,TYPE:.spec.type,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 15: Pod Identity Association ──────────────────────────────────
  section "2.16  Pod Identity Associations (Layer 15)"
  kubectl get podidentityassociations.eks.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SA:.spec.serviceAccount,ROLE_ARN:.spec.roleARN,ASSOC_ID:.status.associationID,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 16: Secrets Manager (fence-config) ───────────────────────────
  section "2.17  AWS Secrets Manager (Layer 16 — fence-config)"
  kubectl get secrets.secretsmanager.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,SECRET_ARN:.status.ackResourceMetadata.arn,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""
}

# ============================================================================
# PHASE 3: KRO-Managed K8s Secrets (infra outputs, fence-config)
# ============================================================================
report_kro_secrets() {
  header "PHASE 3 — KRO-MANAGED KUBERNETES SECRETS"

  section "3.1  Infrastructure Outputs Secret"
  note "Non-sensitive infra outputs bridging RGD → downstream consumers"
  INFRA_SECRET=$(kubectl get secret -n "$NAMESPACE" -l gen3.io/infra-outputs=true -o json 2>/dev/null || echo "")
  if [[ -n "$INFRA_SECRET" ]] && echo "$INFRA_SECRET" | jq -e '.items | length > 0' &>/dev/null; then
    echo "$INFRA_SECRET" | jq -r '.items[] | "  Name: \(.metadata.name)\n  Keys: \(.data | keys | join(", "))\n  Labels: \(.metadata.labels | to_entries | map("\(.key)=\(.value)") | join(", "))"'
    echo ""
    ok "Infra outputs secret present ($(echo "$INFRA_SECRET" | jq '.items[0].data | keys | length') keys)"
  else
    # Fallback: match by naming convention
    if kubectl get secret "${INSTANCE_NAME:-}-infra-outputs" -n "$NAMESPACE" &>/dev/null; then
      echo "  Name: ${INSTANCE_NAME}-infra-outputs"
      KEYS=$(kubectl get secret "${INSTANCE_NAME}-infra-outputs" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.data | keys | join(", ")')
      echo "  Keys: $KEYS"
      KEY_COUNT=$(kubectl get secret "${INSTANCE_NAME}-infra-outputs" -n "$NAMESPACE" -o json 2>/dev/null | jq '.data | keys | length')
      ok "Infra outputs secret present ($KEY_COUNT keys, matched by naming convention)"
    else
      warn "No infrastructure outputs secret found"
    fi
  fi

  echo ""
  section "3.2  Fence Config Content Secret (CSOC-side staging)"
  note "K8s Secret staging fence-config YAML before ACK pushes to Secrets Manager"
  FENCE_SECRET=$(kubectl get secret -n "$NAMESPACE" -l gen3.io/component=fence-config -o json 2>/dev/null || echo "")
  if [[ -n "$FENCE_SECRET" ]] && echo "$FENCE_SECRET" | jq -e '.items | length > 0' &>/dev/null; then
    echo "$FENCE_SECRET" | jq -r '.items[] | "  Name: \(.metadata.name)\n  Keys: \(.data | keys | join(", "))"'
    echo ""
    ok "Fence config content secret present"
  else
    # Fallback: try by name convention
    if kubectl get secret "${INSTANCE_NAME:-}-fence-config-content" -n "$NAMESPACE" &>/dev/null; then
      echo "  Name: ${INSTANCE_NAME}-fence-config-content"
      ok "Fence config content secret present (matched by naming convention)"
    else
      warn "No fence config content secret found"
    fi
  fi
  echo ""
}

# ============================================================================
# PHASE 4: ArgoCD Integration
# ============================================================================
report_argocd() {
  header "PHASE 4 — ARGOCD INTEGRATION"

  section "4.1  ArgoCD Cluster Secrets (Spoke Registration)"
  note "Registers spoke EKS cluster with CSOC ArgoCD"
  kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster -o json 2>/dev/null \
    | jq -r --arg ns "$NAMESPACE" '
      .items[]
      | select(
          (.metadata.name | test($ns)) or
          ((.metadata.annotations // {})["gen3.io/spoke-alias"] // "" | test($ns))
        )
      | [.metadata.name, (.metadata.labels.fleet_member // "unknown"), (.metadata.labels.environment // "n/a"), .metadata.creationTimestamp]
      | @tsv' \
    | awk 'BEGIN { printf "%-30s %-20s %-12s %s\n", "NAME", "FLEET_MEMBER", "ENVIRONMENT", "AGE" }
           { printf "%-30s %-20s %-12s %s\n", $1, $2, $3, $4 }' \
    || echo "(none)"

  echo ""
  section "4.2  ArgoCD Applications"
  note "Applications targeting this spoke (infra + workload)"
  kubectl get applications -n argocd -o json 2>/dev/null \
    | jq -r --arg ns "$NAMESPACE" '
      .items[]
      | select(
          (.metadata.name | startswith($ns + "-")) or
          (.spec.destination.name // "" | startswith($ns)) or
          ((.spec.destination.namespace // "") == $ns)
        )
      | [
          .metadata.name,
          (.spec.destination.name // .spec.destination.server // "unknown"),
          (.status.sync.status // "Unknown"),
          (.status.health.status // "Unknown"),
          (if .spec.syncPolicy.automated then "auto" else "manual" end),
          (.metadata.annotations["argocd.argoproj.io/sync-wave"] // "n/a")
        ]
      | @tsv' \
    | awk 'BEGIN { printf "%-30s %-20s %-12s %-12s %-8s %s\n", "NAME", "DESTINATION", "SYNC", "HEALTH", "MODE", "WAVE" }
           { printf "%-30s %-20s %-12s %-12s %-8s %s\n", $1, $2, $3, $4, $5, $6 }' \
    || echo "(none)"

  # Show any conditions on applications
  echo ""
  APPS_WITH_CONDITIONS=$(kubectl get applications -n argocd -o json 2>/dev/null \
    | jq -r --arg ns "$NAMESPACE" '
      .items[]
      | select(.metadata.name | startswith($ns + "-"))
      | select(.status.conditions // [] | length > 0)
      | "\(.metadata.name): \(.status.conditions | map(.message) | join("; "))"')
  if [[ -n "$APPS_WITH_CONDITIONS" ]]; then
    warn "Applications with conditions:"
    echo "$APPS_WITH_CONDITIONS" | while read -r line; do
      echo "  $line"
    done
  fi
  echo ""
}

# ============================================================================
# SUMMARY
# ============================================================================
report_summary() {
  header "SUMMARY"

  # Gather key data
  local instance_name vpc_id eks_name eks_status aurora_ep aurora_status kro_ready
  instance_name=$(kubectl get awsgen3infra1flat -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "None")
  vpc_id=$(kubectl get vpcs.ec2.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.vpcID}' 2>/dev/null || echo "None")
  eks_name=$(kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "None")
  eks_status=$(kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.status}' 2>/dev/null || echo "None")
  aurora_ep=$(kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.endpoint}' 2>/dev/null || echo "None")
  aurora_status=$(kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.status}' 2>/dev/null || echo "None")
  kro_ready=$(kubectl get awsgen3infra1flat -n "$NAMESPACE" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

  echo -e "${BOLD}Instance:${RESET}        $instance_name"
  echo -e "${BOLD}Namespace:${RESET}       $NAMESPACE"
  echo -e "${BOLD}KRO Ready:${RESET}       $kro_ready"
  echo -e "${BOLD}VPC ID:${RESET}          $vpc_id"
  echo -e "${BOLD}EKS Cluster:${RESET}     $eks_name ($eks_status)"
  echo -e "${BOLD}Aurora:${RESET}          $aurora_ep ($aurora_status)"

  echo ""
  echo -e "${BOLD}Resource Counts:${RESET}"
  printf "  %-28s %s\n" "KMS Keys:" "$(kcount keys.kms.services.k8s.aws)"
  printf "  %-28s %s\n" "VPCs:" "$(kcount vpcs.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "Internet Gateways:" "$(kcount internetgateways.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "Subnets:" "$(kcount subnets.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "Elastic IPs:" "$(kcount elasticipaddresses.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "NAT Gateways:" "$(kcount natgateways.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "Route Tables:" "$(kcount routetables.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "Security Groups:" "$(kcount securitygroups.ec2.services.k8s.aws)"
  printf "  %-28s %s\n" "IAM Roles:" "$(kcount roles.iam.services.k8s.aws)"
  printf "  %-28s %s\n" "S3 Buckets:" "$(kcount buckets.s3.services.k8s.aws)"
  printf "  %-28s %s\n" "DB Subnet Groups:" "$(kcount dbsubnetgroups.rds.services.k8s.aws)"
  printf "  %-28s %s\n" "Aurora Clusters:" "$(kcount dbclusters.rds.services.k8s.aws)"
  printf "  %-28s %s\n" "Aurora Instances:" "$(kcount dbinstances.rds.services.k8s.aws)"
  printf "  %-28s %s\n" "EKS Clusters:" "$(kcount clusters.eks.services.k8s.aws)"
  printf "  %-28s %s\n" "EKS Access Entries:" "$(kcount accessentries.eks.services.k8s.aws)"
  printf "  %-28s %s\n" "Pod Identity Associations:" "$(kcount podidentityassociations.eks.services.k8s.aws)"
  printf "  %-28s %s\n" "Secrets Manager Secrets:" "$(kcount secrets.secretsmanager.services.k8s.aws)"

  # ACK sync check
  echo ""
  echo -e "${BOLD}ACK Sync Status:${RESET}"
  local total=0 synced=0 unsynced=0
  for rt in keys.kms vpcs.ec2 internetgateways.ec2 subnets.ec2 elasticipaddresses.ec2 natgateways.ec2 routetables.ec2 securitygroups.ec2 roles.iam buckets.s3 dbsubnetgroups.rds dbclusters.rds dbinstances.rds clusters.eks accessentries.eks podidentityassociations.eks secrets.secretsmanager; do
    while read -r line; do
      [[ -z "$line" ]] && continue
      # Extract last field (SYNCED) and everything before it (NAME, possibly with spaces)
      local sync_val name_val
      sync_val=$(echo "$line" | awk '{print $NF}')
      name_val=$(echo "$line" | awk '{$NF=""; sub(/[[:space:]]+$/, ""); print}')
      total=$((total + 1))
      if [[ "$sync_val" == "True" ]]; then
        synced=$((synced + 1))
      else
        unsynced=$((unsynced + 1))
        warn "Not synced: $rt — $name_val ($sync_val)"
      fi
    done < <(kubectl get "${rt}.services.k8s.aws" -n "$NAMESPACE" \
      -o custom-columns='NAME:.metadata.name,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' \
      --no-headers 2>/dev/null)
  done

  if [[ $unsynced -eq 0 ]]; then
    ok "All $total ACK resources synced"
  else
    warn "$synced/$total synced, $unsynced unsynced"
  fi

  echo ""
}

# ── Main ───────────────────────────────────────────────────────────────────
report_pre_rgd
report_rgd_resources
report_kro_secrets
report_argocd
report_summary

echo ""
note "═══════════════════════════════════════════════════════════"
note "End of report for namespace: $NAMESPACE"
if [[ "$SAVE_REPORT" == true ]]; then
  note "Report saved to: $REPORT_FILE"
fi
note "Generated: $TIMESTAMP"
note "═══════════════════════════════════════════════════════════"
echo ""
