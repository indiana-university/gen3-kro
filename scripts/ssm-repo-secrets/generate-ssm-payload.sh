#!/usr/bin/env bash
###############################################################################
# generate-ssm-payload.sh
#
# Reads input.json (GitHub App credentials per repo) and produces output.json
# containing the SSM-ready payloads, including the GitHub App Installation ID
# obtained from the GitHub API.
#
# Usage:
#   bash generate-ssm-payload.sh [input.json] [output.json]
#
# Defaults:
#   input.json  = config/ssm-repo-secrets/input.json
#   output.json = outputs/ssm-repo-secrets/output.json
#
# input.json schema:
# {
#   "repos": [
#     {
#       "name": "eks-cluster-mgmt",
#       "ssm_secret_name": "/gen3-kro-csoc/eks-cluster-mgmt/git-credentials",
#       "github_url": "github.iu.edu",
#       "org_name": "RDServices",
#       "repo_name": "eks-cluster-mgmt",
#       "github_app_id": "12345",
#       "github_app_private_key_file": "/path/to/private-key.pem",
#       "github_app_client_secret": "31aa795dbba47c2ca17061fa3f07b6e9f5bed44c"
#     }
#   ]
# }
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUTS_DIR="${REPO_ROOT}/outputs"
LOG_DIR="${OUTPUTS_DIR}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/ssm-generate-$(date +%Y%m%d-%H%M%S).log"

main() {
INPUT_FILE="${1:-${REPO_ROOT}/config/ssm-repo-secrets/input.json}"
OUTPUT_FILE="${2:-${REPO_ROOT}/outputs/ssm-repo-secrets/output.json}"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "=== No input.json found at $INPUT_FILE ==="
  echo "  Writing empty output: $OUTPUT_FILE"
  echo '{"repos": []}' > "$OUTPUT_FILE"
  echo "  No repos to process — done."
  exit 0
fi

# Check for empty repos list
REPO_COUNT_CHECK=$(jq '.repos | length' "$INPUT_FILE" 2>/dev/null || echo "0")
if [[ "$REPO_COUNT_CHECK" -eq 0 ]]; then
  echo "=== input.json has empty repos list ==="
  echo "  Writing empty output: $OUTPUT_FILE"
  echo '{"repos": []}' > "$OUTPUT_FILE"
  echo "  No repos to process — done."
  exit 0
fi

# Validate prerequisites
for cmd in openssl curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Required command '$cmd' not found" >&2
    exit 1
  fi
done

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "=== Generating SSM Payloads ==="
echo "  Input:  $INPUT_FILE"
echo "  Output: $OUTPUT_FILE"
echo ""

# Pure bash JWT generation (no extra packages needed)
b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }

generate_jwt() {
  local app_id="$1"
  local pem
  pem=$(cat "$2")

  local now iat exp
  now=$(date +%s)
  iat=$((now - 60))
  exp=$((now + 600))

  local header
  header=$(echo -n '{"typ":"JWT","alg":"RS256"}' | b64enc)

  local payload
  payload=$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":${app_id}}" | b64enc)

  local header_payload="${header}.${payload}"

  local signature
  signature=$(
    openssl dgst -sha256 -sign <(echo -n "${pem}") \
      <(echo -n "${header_payload}") | b64enc
  )

  echo "${header_payload}.${signature}"
}

# Process each repo entry
REPO_COUNT=$(jq '.repos | length' "$INPUT_FILE")
echo "  Found $REPO_COUNT repo(s) to process"
echo ""

# Start building output JSON
OUTPUT_ENTRIES="[]"

for i in $(seq 0 $((REPO_COUNT - 1))); do
  REPO_NAME=$(jq -r ".repos[$i].name" "$INPUT_FILE")
  SSM_SECRET_NAME=$(jq -r ".repos[$i].ssm_secret_name" "$INPUT_FILE")
  GITHUB_URL=$(jq -r ".repos[$i].github_url" "$INPUT_FILE")
  ORG_NAME=$(jq -r ".repos[$i].org_name" "$INPUT_FILE")
  REPO=$(jq -r ".repos[$i].repo_name" "$INPUT_FILE")
  APP_ID=$(jq -r ".repos[$i].github_app_id" "$INPUT_FILE")
  CLIENT_ID=$(jq -r ".repos[$i].github_client_id" "$INPUT_FILE")
  KEY_FILE=$(jq -r ".repos[$i].github_app_private_key_file" "$INPUT_FILE")

  echo "--- Processing: $REPO_NAME ---"
  echo "  GitHub:     https://$GITHUB_URL/$ORG_NAME/$REPO"
  echo "  App ID:     $APP_ID"
  echo "  Client ID:  $CLIENT_ID"
  echo "  SSM Path:   $SSM_SECRET_NAME"

  # Resolve private key file path (relative to repo root)
  if [[ ! "$KEY_FILE" = /* ]]; then
    KEY_FILE="$REPO_ROOT/$KEY_FILE"
  fi

  if [[ ! -f "$KEY_FILE" ]]; then
    echo "  ERROR: Private key file not found: $KEY_FILE" >&2
    exit 1
  fi

  # Read private key content
  PRIVATE_KEY_CONTENT=$(cat "$KEY_FILE")

  # Generate JWT using App ID (integer) as issuer
  echo "  Generating JWT..."
  JWT=$(generate_jwt "$APP_ID" "$KEY_FILE")

  if [[ -z "$JWT" ]]; then
    echo "  ERROR: Failed to generate JWT" >&2
    exit 1
  fi

  # Determine API base URL
  if [[ "$GITHUB_URL" == "github.com" ]]; then
    API_BASE="https://api.github.com"
    APP_BASE_URL=""
  else
    API_BASE="https://$GITHUB_URL/api/v3"
    APP_BASE_URL="https://$GITHUB_URL/api/v3"
  fi

  # Get installation ID from GitHub API
  echo "  Querying GitHub API for installation ID..."
  local_response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $JWT" \
    -H "Accept: application/vnd.github+json" \
    "$API_BASE/app/installations")
  http_code=$(echo "$local_response" | tail -1)
  INSTALLATIONS=$(echo "$local_response" | sed '$d')

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "  ERROR: GitHub API returned HTTP $http_code from $API_BASE/app/installations" >&2
    echo "  Response: $INSTALLATIONS" >&2
    exit 1
  fi

  # Find the installation for our org
  INSTALLATION_ID=$(echo "$INSTALLATIONS" | jq -r \
    --arg org "$ORG_NAME" \
    '[.[] | select(.account.login == $org)] | .[0].id // empty')

  if [[ -z "$INSTALLATION_ID" || "$INSTALLATION_ID" == "null" ]]; then
    echo "  WARNING: No installation found for org '$ORG_NAME'. Listing available:" >&2
    echo "$INSTALLATIONS" | jq '[.[] | {id: .id, account: .account.login, type: .account.type}]' >&2
    echo "" >&2
    echo "  Trying repo-level installation lookup..." >&2

    # Try repo-level lookup
    REPO_INSTALLATION=$(curl -sf \
      -H "Authorization: Bearer $JWT" \
      -H "Accept: application/vnd.github+json" \
      "$API_BASE/repos/$ORG_NAME/$REPO/installation" 2>&1) || true

    INSTALLATION_ID=$(echo "$REPO_INSTALLATION" | jq -r '.id // empty' 2>/dev/null)

    if [[ -z "$INSTALLATION_ID" || "$INSTALLATION_ID" == "null" ]]; then
      echo "  ERROR: Could not find installation ID for $ORG_NAME/$REPO" >&2
      exit 1
    fi
  fi

  echo "  Installation ID: $INSTALLATION_ID"

  # Build the SSM secret payload (ArgoCD repo secret format)
  REPO_URL="https://$GITHUB_URL/$ORG_NAME/$REPO"

  SECRET_PAYLOAD=$(jq -n \
    --arg appBaseUrl "$APP_BASE_URL" \
    --arg appID "$APP_ID" \
    --arg installID "$INSTALLATION_ID" \
    --arg privKey "$PRIVATE_KEY_CONTENT" \
    --arg type "git" \
    --arg url "$REPO_URL" \
    '{
      githubAppEnterpriseBaseUrl: $appBaseUrl,
      githubAppID: $appID,
      githubAppInstallationID: $installID,
      githubAppPrivateKey: $privKey,
      type: $type,
      url: $url
    }')

  # Add to output array
  OUTPUT_ENTRIES=$(echo "$OUTPUT_ENTRIES" | jq \
    --arg name "$REPO_NAME" \
    --arg ssm "$SSM_SECRET_NAME" \
    --argjson payload "$SECRET_PAYLOAD" \
    '. + [{
      name: $name,
      ssm_secret_name: $ssm,
      payload: $payload
    }]')

  echo "  Done."
  echo ""
done

# Write output
jq -n --argjson repos "$OUTPUT_ENTRIES" '{ repos: $repos }' > "$OUTPUT_FILE"

echo "=== Output written to: $OUTPUT_FILE ==="
echo "  $REPO_COUNT repo secret(s) ready for upload."
echo ""
echo "Next step: run push-ssm-secrets.sh to create/update secrets in AWS Secrets Manager"
}

main "$@" 2>&1 | tee -a "$LOG_FILE"
exit "${PIPESTATUS[0]}"
