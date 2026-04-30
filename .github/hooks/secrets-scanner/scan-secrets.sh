#!/usr/bin/env bash
# gen3-kro Secrets Scanner Hook
# Scans files changed during a Copilot coding agent session for accidentally
# leaked secrets, credentials, and AWS account IDs before they are committed.
#
# Environment variables:
#   SCAN_MODE          - "warn" (log only) or "block" (exit non-zero) (default: warn)
#   SCAN_SCOPE         - "diff" (changed files) or "staged" (staged files) (default: diff)
#   SKIP_SECRETS_SCAN  - "true" to disable entirely (default: unset)

set -euo pipefail

if [[ "${SKIP_SECRETS_SCAN:-}" == "true" ]]; then
  exit 0
fi

MODE="${SCAN_MODE:-warn}"
SCOPE="${SCAN_SCOPE:-diff}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Patterns: "NAME|SEVERITY|REGEX"
PATTERNS=(
  "AWS_ACCESS_KEY|critical|AKIA[0-9A-Z]{16}"
  "AWS_SECRET_KEY|critical|aws_secret_access_key[[:space:]]*[:=][[:space:]]*['"]?[A-Za-z0-9/+=]{40}"
  "AWS_ACCOUNT_ID|high|[^0-9a-z][0-9]{12}[^0-9a-z]"
  "GITHUB_PAT|critical|ghp_[0-9A-Za-z]{36}"
  "GITHUB_FINE_GRAINED|critical|github_pat_[0-9A-Za-z_]{82}"
  "PRIVATE_KEY|critical|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
  "BEARER_TOKEN|medium|[Bb]earer[[:space:]]+[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"
  "ARN_WITH_ACCT|high|arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:"
  "GENERIC_SECRET|medium|(secret|password|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*['"]?[A-Za-z0-9_/+=~.-]{8,}"
)

# Files to exclude from scanning
EXCLUDE_PATTERNS=(
  ".git/"
  "references/"
  "outputs/"
  "*.example"
  "*.lock"
  "node_modules/"
)

# Collect files to scan
if [[ "$SCOPE" == "staged" ]]; then
  mapfile -t FILES < <(git diff --cached --name-only 2>/dev/null || true)
else
  mapfile -t FILES < <(git diff --name-only HEAD 2>/dev/null || git status --short | awk '{print $2}' || true)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  exit 0
fi

FINDINGS=0
FINDING_MSGS=()

for FILE in "${FILES[@]}"; do
  [[ -f "$FILE" ]] || continue

  # Skip excluded patterns
  SKIP=false
  for EXCL in "${EXCLUDE_PATTERNS[@]}"; do
    if [[ "$FILE" == *"$EXCL"* ]]; then
      SKIP=true
      break
    fi
  done
  [[ "$SKIP" == "true" ]] && continue

  for PATTERN_ENTRY in "${PATTERNS[@]}"; do
    IFS="|" read -r PNAME SEVERITY REGEX <<< "$PATTERN_ENTRY"
    if grep -qEn "$REGEX" "$FILE" 2>/dev/null; then
      LINE=$(grep -En "$REGEX" "$FILE" 2>/dev/null | head -1 | cut -d: -f1)
      MSG="[$SEVERITY] $PNAME in $FILE (line $LINE)"
      FINDING_MSGS+=("$MSG")
      FINDINGS=$((FINDINGS + 1))
    fi
  done
done

if [[ $FINDINGS -gt 0 ]]; then
  echo ""
  echo "=== gen3-kro Secrets Scanner: $FINDINGS finding(s) at $TIMESTAMP ==="
  for MSG in "${FINDING_MSGS[@]}"; do
    echo "  $MSG"
  done
  echo ""
  echo "Review these files before committing. If these are false positives,"
  echo "set SKIP_SECRETS_SCAN=true or add an exclusion pattern."
  echo ""

  if [[ "$MODE" == "block" ]]; then
    exit 1
  fi
fi

exit 0
