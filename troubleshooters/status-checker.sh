#!/usr/bin/env bash
set -u

usage() {
  cat <<EOF
Usage: $0 [--namespace NAMESPACE] [--outdir OUTDIR]

Defaults:
  NAMESPACE=spoke1
  OUTDIR=outputs/troubleshooting-results

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

echo "WROTE $OUTFILE" >&2
