#!/usr/bin/env bash
# ============================================================================
# Namespace Infrastructure Report — Per-Spoke Resource Inventory
# ============================================================================
# Usage: ./scripts/reports/namespace-infra-report.sh <namespace>
#
# Produces a comprehensive report of infrastructure resources in a spoke
# namespace, organized by deployment phase and dependency order.
#
# Output: stdout + outputs/namespaced-reports/<namespace>-report.ansi
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
  echo "Usage: $0 <namespace> [--no-save] [-t]"
  echo ""
  echo "Example: $0 spoke1"
  echo ""
  echo "Options:"
  echo "  --no-save   Skip saving report to outputs/reports/"
  echo "  -t          Append timestamp to output filename"
  exit 1
fi

NAMESPACE="$1"
SAVE_REPORT=true
ADD_TIMESTAMP=false
shift
for arg in "$@"; do
  case "${arg}" in
    --no-save) SAVE_REPORT=false ;;
    -t)        ADD_TIMESTAMP=true ;;
  esac
done

# Verify namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "Error: namespace '$NAMESPACE' does not exist"
  exit 1
fi

# ── Report output setup ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RGD_DIR="${REPO_ROOT}/argocd/csoc/kro/aws-rgds/gen3/v1"
REPORT_DIR="$REPO_ROOT/outputs/reports"
REPORT_FILENAME="${NAMESPACE}-report"
if [[ "${ADD_TIMESTAMP}" == true ]]; then
  REPORT_FILENAME="${REPORT_FILENAME}-$(date '+%Y%m%d-%H%M%S')"
fi
REPORT_FILE="$REPORT_DIR/${REPORT_FILENAME}.ansi"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [[ "$SAVE_REPORT" == true ]]; then
  mkdir -p "$REPORT_DIR"
  # Use a subshell + tee so all output goes to both stdout and file
  exec > >(tee "$REPORT_FILE") 2>&1
fi

# ── Helpers ────────────────────────────────────────────────────────────────
# Count resources of a given type in namespace
kcount() { kubectl get "$1" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' '; }

# Some graph templates may exist in git before their CRDs are registered.
# Skip those cleanly instead of exiting under set -euo pipefail.
kresource_exists() {
  kubectl get "$1" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
}

# ── Discovery: KRO tier kinds ─────────────────────────────────────────────
# Reads RGD template files (source of truth: repo) for their registered
# resource names.
# Outputs one namespaced API resource name per line, ordered by RGD filename
# prefix.
discover_kro_tiers() {
  python3 - "${RGD_DIR}" << 'PYEOF'
import sys, os, re
rgd_dir = sys.argv[1]
if not os.path.isdir(rgd_dir):
    sys.exit(0)
results = []
for root, _, files in os.walk(rgd_dir):
  for fname in sorted(files):
    if not fname.endswith('-rg.yaml'):
        continue
    fpath = os.path.join(root, fname)
    rel = os.path.relpath(fpath, rgd_dir)
    m = re.search(r'Phase(\d+)', rel)
    order = int(m.group(1)) if m else 99
    try:
        text = open(fpath).read()
    except Exception:
        continue
    # ResourceGraphDefinition names match the generated CRD resource name.
    name_matches = re.findall(r'^\s*name:\s*(awsgen3[^\s#]+)\s*$', text, re.MULTILINE)
    resource_name = next((name for name in name_matches if name.startswith('awsgen3')), None)
    if not resource_name:
        continue
    results.append((order, rel, resource_name))
for _, _, resource_name in sorted(results):
    print(resource_name)
PYEOF
}

# ── Discovery: ACK resource types ─────────────────────────────────────────
# Queries live cluster CRDs for all *.services.k8s.aws types.
# Outputs lines: full_crd_name|human_label|service_group
# Ordered by service group then plural name.
discover_ack_type_map() {
  # NOTE: do NOT pipe kubectl output to 'python3 - << HEREDOC' — in bash the heredoc
  # overrides the pipe for python3's stdin, causing kubectl to SIGPIPE under pipefail.
  # Pass kubectl output via process substitution as sys.argv[1] instead.
  python3 - <(kubectl get crd -o json 2>/dev/null) << 'PYEOF'
import sys, json, re
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
results = []
for item in data.get('items', []):
    group = item.get('spec', {}).get('group', '')
    if not group.endswith('.services.k8s.aws'):
        continue
    plural = item['metadata']['name']
    kind   = item.get('spec', {}).get('names', {}).get('kind', '')
    label  = re.sub(r'(?<=[a-z0-9])([A-Z])', r' \1', kind)
    svc    = group.split('.')[0]
    results.append((svc, plural, label))
for svc, plural, label in sorted(results):
    print(f"{plural}|{label}|{svc}")
PYEOF
}

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
  header "PHASE 2 — RGD-DEPLOYED RESOURCES (KRO Modular Tiers)"

  section "2.0  KRO Tier Instance Status"
  note "Modular RGD instances in namespace '$NAMESPACE'"
  echo ""

  # Discover tier CRD names dynamically from RGD template files
  local -a MODULAR_TIERS
  readarray -t MODULAR_TIERS < <(discover_kro_tiers)

  local found_any=false
  for tier_crd in "${MODULAR_TIERS[@]}"; do
    if ! kresource_exists "${tier_crd}"; then
      note "  ${tier_crd}: (CRD not registered in cluster)"
      echo ""
      continue
    fi
    local count
    count=$(kubectl get "${tier_crd}" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      found_any=true
      note "  ${tier_crd}:"
      kubectl get "${tier_crd}" -n "$NAMESPACE" \
        -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,REASON:.status.conditions[?(@.type=="Ready")].reason,AGE:.metadata.creationTimestamp' 2>/dev/null \
        | sed 's/^/  /'
      # Show any non-ready conditions
      kubectl get "${tier_crd}" -n "$NAMESPACE" -o json 2>/dev/null \
        | jq -r '.items[] | "\(.metadata.name)" as $name | .status.conditions[]? | select(.status != "True") | "    ✗ \($name): \(.type) — \(.message // .reason // "unknown")"'
      echo ""
    fi
  done

  if [[ "$found_any" == false ]]; then
    warn "No modular RGD instances found in namespace '$NAMESPACE'"
    note "  Expected kinds: AwsGen3Network1, AwsGen3Storage1, AwsGen3Database1, ..."
    echo ""
  fi

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

  # ── Layer 17: OpenSearch Domain ────────────────────────────────────────
  section "2.18  OpenSearch Domain (Layer 17 — Search1 tier)"
  kubectl get domains.opensearchservice.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,DOMAIN_NAME:.spec.domainName,STATUS:.status.processing,ENDPOINT:.status.endpoint,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 18: ElastiCache Replication Group (Redis) ────────────────────
  section "2.19  ElastiCache Replication Group (Layer 18 — Search1 optional Redis)"
  kubectl get replicationgroups.elasticache.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.status,PRIMARY_ENDPOINT:.status.nodeGroups[0].primaryEndpoint.address,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 19: SQS Queues ───────────────────────────────────────────────
  section "2.20  SQS Queues (Layer 19 — Messaging1 tier)"
  kubectl get queues.sqs.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,QUEUE_URL:.status.queueURL,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 20: ACM Certificates ─────────────────────────────────────────
  section "2.21  ACM Certificates (Layer 20 — DNS1 tier)"
  kubectl get certificates.acm.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ARN:.status.ackResourceMetadata.arn,STATUS:.status.status,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""

  # ── Layer 21: WAFv2 WebACL ─────────────────────────────────────────────
  section "2.22  WAFv2 WebACL (Layer 21 — Advanced1 tier)"
  kubectl get webacls.wafv2.services.k8s.aws -n "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,ARN:.status.ackResourceMetadata.arn,SYNCED:.status.conditions[?(@.type=="ACK.ResourceSynced")].status' 2>/dev/null \
    || echo "(none)"
  echo ""
}

# ============================================================================
# PHASE 3: KRO Bridge ConfigMaps (inter-tier data passing)
# ============================================================================
report_kro_bridges() {
  header "PHASE 3 — KRO BRIDGE CONFIGMAPS"

  section "3.1  Bridge ConfigMaps"
  note "Inter-RGD bridges — produced by each tier, consumed by downstream tiers"
  local bridge_list
  bridge_list=$(kubectl get configmaps -n "$NAMESPACE" --no-headers 2>/dev/null \
    | awk '$1 ~ /-bridge($|-)/' || true)

  if [[ -n "$bridge_list" ]]; then
    printf "  %-42s %-6s %s\n" "NAME" "KEYS" "AGE"
    while read -r cm_name _ cm_age; do
      local key_count
      key_count=$(kubectl get configmap "${cm_name}" -n "$NAMESPACE" -o json 2>/dev/null \
        | jq '.data | length // 0')
      printf "  %-42s %-6s %s\n" "${cm_name}" "${key_count}" "${cm_age}"
    done < <(printf '%s\n' "$bridge_list")
    echo ""
    ok "$(echo "$bridge_list" | wc -l | tr -d ' ') bridge ConfigMap(s) present"
  else
    warn "No bridge ConfigMaps found in namespace '$NAMESPACE'"
    note "  Bridge ConfigMaps are created by each completed tier (e.g., spoke1-foundation-bridge)"
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
  local vpc_id eks_name eks_status aurora_ep aurora_status
  vpc_id=$(kubectl get vpcs.ec2.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.vpcID}' 2>/dev/null || echo "None")
  eks_name=$(kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "None")
  eks_status=$(kubectl get clusters.eks.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.status}' 2>/dev/null || echo "None")
  aurora_ep=$(kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.endpoint}' 2>/dev/null || echo "None")
  aurora_status=$(kubectl get dbclusters.rds.services.k8s.aws -n "$NAMESPACE" -o jsonpath='{.items[0].status.status}' 2>/dev/null || echo "None")

  echo -e "${BOLD}Namespace:${RESET}       $NAMESPACE"
  echo -e "${BOLD}VPC ID:${RESET}          $vpc_id"
  echo -e "${BOLD}EKS Cluster:${RESET}     $eks_name ($eks_status)"
  echo -e "${BOLD}Aurora:${RESET}          $aurora_ep ($aurora_status)"

  echo ""
  echo -e "${BOLD}KRO Tier Readiness:${RESET}"
  local all_tiers_ready=true
  local any_tier_found=false
  # Discover tier list from RGD templates — same source as Phase 2
  local -a _tier_list
  readarray -t _tier_list < <(discover_kro_tiers)
  for tier_crd in "${_tier_list[@]}"; do
    if ! kresource_exists "${tier_crd}"; then
      note "  ${tier_crd}: not registered"
      continue
    fi
    local count
    count=$(kubectl get "${tier_crd}" -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      any_tier_found=true
      local tier_ready instance_nm
      tier_ready=$(kubectl get "${tier_crd}" -n "$NAMESPACE" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
      instance_nm=$(kubectl get "${tier_crd}" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "?")
      if [[ "$tier_ready" == "True" ]]; then
        ok "$(printf '%-32s' "${tier_crd}") ${instance_nm}"
      else
        warn "$(printf '%-32s' "${tier_crd}") ${instance_nm} (${tier_ready})"
        all_tiers_ready=false
      fi
    fi
  done
  if [[ "$any_tier_found" == false ]]; then
    warn "No modular RGD instances found in namespace '$NAMESPACE'"
  fi

  echo ""
  echo -e "${BOLD}Resource Counts:${RESET}"
  local -a _ack_type_map
  readarray -t _ack_type_map < <(discover_ack_type_map)
  if [[ ${#_ack_type_map[@]} -gt 0 ]]; then
    for entry in "${_ack_type_map[@]}"; do
      IFS='|' read -r plural label _ <<< "${entry}"
      printf "  %-32s %s\n" "${label}:" "$(kcount "${plural}")"
    done
  else
    note "  (no ACK CRDs installed — kubectl CRD query returned nothing)"
  fi

  # ACK sync check
  echo ""
  echo -e "${BOLD}ACK Sync Status:${RESET}"
  local total=0 synced=0 unsynced=0
  for entry in "${_ack_type_map[@]}"; do
    IFS='|' read -r plural label _ <<< "${entry}"
    while read -r line; do
      [[ -z "$line" ]] && continue
      local sync_val name_val
      sync_val=$(echo "$line" | awk '{print $NF}')
      name_val=$(echo "$line" | awk '{$NF=""; sub(/[[:space:]]+$/, ""); print}')
      total=$((total + 1))
      if [[ "$sync_val" == "True" ]]; then
        synced=$((synced + 1))
      else
        unsynced=$((unsynced + 1))
        warn "Not synced: ${plural} — ${name_val} (${sync_val})"
      fi
    done < <(kubectl get "${plural}" -n "$NAMESPACE" \
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
report_kro_bridges
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
