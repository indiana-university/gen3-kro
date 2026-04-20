#!/usr/bin/env bash
###############################################################################
# status-checker.sh — Comprehensive spoke status report
#
# Sections:
#   1. ACK resource statuses in the spoke namespace (CSOC cluster)
#   2. ArgoCD Applications targeting the spoke
#   3. Workloads running on the spoke cluster (via ArgoCD exec proxy)
#
# Usage: $0 [--namespace NAMESPACE] [--outdir OUTDIR]
###############################################################################
set -u

usage() {
  cat <<EOF
Usage: $0 [--namespace NAMESPACE] [--outdir OUTDIR]

Defaults:
  NAMESPACE=spoke1
  OUTDIR=outputs/troubleshooting-results

Sections:
  1. ACK Resources    — CRD statuses in the spoke namespace (on CSOC cluster)
  2. ArgoCD Apps      — All ArgoCD apps targeting this spoke
  3. Spoke Workloads  — Pods/Deployments on the spoke cluster (via ArgoCD proxy)

Examples:
  $0 --namespace spoke1
  $0 spoke1
EOF
}

NS="spoke1"
OUTDIR="outputs/troubleshooting-results"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      NS="$2"; shift 2;;
    -o|--outdir)
      OUTDIR="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    --)
      shift; break;;
    -* )
      echo "Unknown option: $1" >&2; usage; exit 1;;
    * )
      # positional namespace
      NS="$1"; shift;;
  esac
done

mkdir -p "$OUTDIR"
OUTFILE="$OUTDIR/${NS}-status.yaml"
: > "$OUTFILE"

###############################################################################
# SECTION 1: ACK Resource Statuses (on CSOC cluster)
###############################################################################

kinds=(
  vpc
  subnet
  internetgateway
  routetable
  natgateway
  elasticipaddress
  securitygroup
  key
  bucket
  dbsubnetgroup
  dbcluster
  accessentry
  podidentityassociation
  cluster
  roles.iam.services.k8s.aws
  replicationgroup
  domains.opensearchservice.services.k8s.aws
)

echo "=== Section 1: ACK Resource Statuses (namespace: $NS) ===" >> "$OUTFILE"
echo "Collecting ACK resource statuses in namespace '$NS' -> $OUTFILE" >&2

for kind in "${kinds[@]}"; do
  resources_json=$(kubectl get "$kind" -n "$NS" -o json 2>/dev/null)
  item_count=$(echo "${resources_json:-{\}}" | jq '.items | length' 2>/dev/null || echo 0)
  if [ "$item_count" -eq 0 ]; then
    continue
  fi

  # Emit one compact status block per resource showing kind, name, and conditions
  echo "$resources_json" | jq -r '
    .items[] |
    . as $item |
    (if ($item.status | type) == "object" then ($item.status.conditions // []) else [] end) as $conds |
    (
      "---\n" +
      "kind:   " + ($item.kind // "Unknown") + "\n" +
      "name:   " + ($item.metadata.name // "Unknown") + "\n" +
      if ($conds | length) == 0 then
        "conditions: []"
      else
        "conditions:\n" +
        ($conds | map(
          "  - type: "    + (.type    // "") + "\n" +
          "    status: "  + (.status  // "") + "\n" +
          "    reason: "  + ((.reason  // "") | tostring) + "\n" +
          "    message: " + ((.message // "") | tostring | .[0:200])
        ) | join("\n"))
      end
    )
  ' >> "$OUTFILE"
done

###############################################################################
# SECTION 2: ArgoCD Applications targeting this spoke
###############################################################################

echo "" >> "$OUTFILE"
echo "=== Section 2: ArgoCD Applications (spoke: $NS) ===" >> "$OUTFILE"
echo "Collecting ArgoCD application statuses for spoke '$NS'" >&2

# Find all ArgoCD apps that target this spoke (by label or destination name)
# The spoke alias is used as the label fleet_spoke=<alias> and in the app name.
argocd_apps_json=$(kubectl get applications.argoproj.io -n argocd -o json 2>/dev/null || echo '{"items":[]}')

echo "$argocd_apps_json" | jq -r --arg ns "$NS" '
  .items[] |
  select(
    (.metadata.labels.fleet_spoke // "") == $ns or
    (.metadata.name | test("^" + $ns + "-")) or
    (.spec.destination.name // "" | test("^" + $ns))
  ) |
  (
    "---\n" +
    "app:         " + (.metadata.name // "Unknown") + "\n" +
    "syncStatus:  " + (.status.sync.status // "Unknown") + "\n" +
    "healthStatus: " + (.status.health.status // "Unknown") + "\n" +
    "destination:  " + (.spec.destination.name // "in-cluster") + "\n" +
    "namespace:    " + (.spec.destination.namespace // "default") + "\n" +
    if (.status.conditions // [] | length) > 0 then
      "conditions:\n" +
      (.status.conditions | map(
        "  - type: "    + (.type // "") + "\n" +
        "    message: " + ((.message // "") | tostring | .[0:200])
      ) | join("\n"))
    else
      "conditions: []"
    end
  )
' >> "$OUTFILE"

# Count summary
app_total=$(echo "$argocd_apps_json" | jq --arg ns "$NS" '[.items[] | select((.metadata.labels.fleet_spoke // "") == $ns or (.metadata.name | test("^" + $ns + "-")) or (.spec.destination.name // "" | test("^" + $ns)))] | length')
app_synced=$(echo "$argocd_apps_json" | jq --arg ns "$NS" '[.items[] | select(((.metadata.labels.fleet_spoke // "") == $ns or (.metadata.name | test("^" + $ns + "-")) or (.spec.destination.name // "" | test("^" + $ns))) and .status.sync.status == "Synced")] | length')
app_healthy=$(echo "$argocd_apps_json" | jq --arg ns "$NS" '[.items[] | select(((.metadata.labels.fleet_spoke // "") == $ns or (.metadata.name | test("^" + $ns + "-")) or (.spec.destination.name // "" | test("^" + $ns))) and .status.health.status == "Healthy")] | length')

{
  echo ""
  echo "# Summary: ${app_synced}/${app_total} Synced, ${app_healthy}/${app_total} Healthy"
} >> "$OUTFILE"

###############################################################################
# SECTION 3: Spoke Cluster Workloads (via ArgoCD server exec proxy)
###############################################################################

echo "" >> "$OUTFILE"
echo "=== Section 3: Spoke Cluster Workloads (spoke: $NS) ===" >> "$OUTFILE"
echo "Collecting workloads on spoke cluster '$NS'" >&2

# The spoke cluster is registered in ArgoCD with data.name = spoke-alias.
# We query via argocd CLI exec'd inside the argocd-server pod to reach the
# spoke cluster. Alternatively, if the spoke kubeconfig context is available
# locally, we use that directly.

# Try 1: Direct kubectl context (spoke alias matches kubeconfig context name)
spoke_context=""
if kubectl config get-contexts -o name 2>/dev/null | grep -qx "$NS"; then
  # Verify the context actually works before using it
  if kubectl cluster-info --context "$NS" &>/dev/null; then
    spoke_context="$NS"
  fi
fi

# Try 2: Check for spoke-dev context pattern
if [[ -z "$spoke_context" ]]; then
  spoke_match=$(kubectl config get-contexts -o name 2>/dev/null | grep "^${NS}" | head -1)
  if [[ -n "$spoke_match" ]]; then
    # Verify connectivity
    if kubectl cluster-info --context "$spoke_match" &>/dev/null; then
      spoke_context="$spoke_match"
    fi
  fi
fi

if [[ -n "$spoke_context" ]]; then
  echo "Using local kubeconfig context: $spoke_context" >&2

  # Deployments
  echo "" >> "$OUTFILE"
  echo "# Deployments:" >> "$OUTFILE"
  deploy_json=$(kubectl get deploy --all-namespaces -o json --context "$spoke_context" 2>/dev/null || echo '{"items":[]}')
  echo "$deploy_json" | jq -r '
    .items[] |
    "---\n" +
    "kind:       Deployment\n" +
    "namespace:  " + .metadata.namespace + "\n" +
    "name:       " + .metadata.name + "\n" +
    "ready:      " + "\(.status.readyReplicas // 0)/\(.spec.replicas // 0)\n" +
    "available:  " + "\(.status.availableReplicas // 0)\n" +
    "conditions:\n" +
    ((.status.conditions // []) | map(
      "  - type: "   + (.type // "") + "\n" +
      "    status: " + (.status // "")
    ) | join("\n"))
  ' >> "$OUTFILE"

  # Pods
  echo "" >> "$OUTFILE"
  echo "# Pods:" >> "$OUTFILE"
  kubectl get pods --all-namespaces --context "$spoke_context" \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount' \
    --no-headers 2>/dev/null >> "$OUTFILE" || echo "  (unable to list pods)" >> "$OUTFILE"

else
  # Fallback: Query ArgoCD's resource tree for managed resources on the spoke
  # ArgoCD already proxies to the spoke; its resource tree has workload status.
  echo "No reachable kubeconfig context for '$NS' — querying ArgoCD resource tree" >&2

  # Find the gen3 app for this spoke (e.g. spoke1-gen3)
  gen3_app="${NS}-gen3"
  cr_app="${NS}-cluster-resources"

  for app_name in "$gen3_app" "$cr_app"; do
    app_exists=$(kubectl get application "$app_name" -n argocd --no-headers 2>/dev/null | wc -l)
    if [[ "$app_exists" -eq 0 ]]; then
      echo "  (app '$app_name' not found)" >> "$OUTFILE"
      continue
    fi

    echo "" >> "$OUTFILE"
    echo "# Resources managed by $app_name:" >> "$OUTFILE"

    kubectl get application "$app_name" -n argocd -o json 2>/dev/null | jq -r '
      (.status.resources // [])[] |
      "  " + .kind + "/" + .name +
      "  sync=" + (.status // "Unknown") +
      "  health=" + (.health.status // "N/A")
    ' >> "$OUTFILE" 2>/dev/null || echo "  (unable to read resource tree)" >> "$OUTFILE"
  done
fi

###############################################################################
# DONE
###############################################################################

echo "" >> "$OUTFILE"
echo "=== Report Complete ===" >> "$OUTFILE"
echo "WROTE $OUTFILE" >&2
