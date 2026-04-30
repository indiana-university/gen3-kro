#!/usr/bin/env bash
# gen3-kro Tool Guardian Hook
# Blocks dangerous operations (destructive git ops, cluster/namespace deletion,
# force-pushes, terraform destroy without confirmation) before Copilot executes them.
#
# Environment variables:
#   GUARD_MODE           - "warn" (log only) or "block" (exit non-zero) (default: block)
#   SKIP_TOOL_GUARD      - "true" to disable entirely (default: unset)

set -euo pipefail

if [[ "${SKIP_TOOL_GUARD:-}" == "true" ]]; then
  exit 0
fi

MODE="${GUARD_MODE:-block}"
INPUT=$(cat)

# Extract command text for pattern matching
TOOL_INPUT=""
if command -v jq &>/dev/null; then
  TOOL_INPUT=$(printf "%s" "$INPUT" | jq -r ".toolInput // .command // empty" 2>/dev/null || true)
fi
if [[ -z "$TOOL_INPUT" ]]; then
  TOOL_INPUT=$(printf "%s" "$INPUT" | grep -oE '"(toolInput|command)"[[:space:]]*:[[:space:]]*"[^"]*"' | sed "s/.*: "//;s/"//" || true)
fi

# ── Dangerous patterns ──────────────────────────────────────────────────────
DANGEROUS_PATTERNS=(
  "git push.*--force"
  "git push.*-f[[:space:]]"
  "git reset.*--hard"
  "git clean.*-fd"
  "kubectl delete namespace"
  "kubectl delete cluster"
  "kind delete cluster"
  "terraform destroy"
  "terragrunt destroy"
  "rm -rf /"
  "rm -rf \."
  "DROP (TABLE|DATABASE|SCHEMA)"
  "aws.*delete-cluster"
  "aws.*delete-stack"
)

FINDING=""
for PAT in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$TOOL_INPUT" | grep -qiE "$PAT" 2>/dev/null; then
    FINDING="$PAT"
    break
  fi
done

if [[ -n "$FINDING" ]]; then
  echo ""
  echo "=== gen3-kro Tool Guardian: BLOCKED ==="
  echo "Dangerous pattern detected: $FINDING"
  echo "Command: $TOOL_INPUT"
  echo ""
  echo "This operation requires explicit user confirmation."
  echo "Set SKIP_TOOL_GUARD=true to allow this specific operation."
  echo ""

  if [[ "$MODE" == "block" ]]; then
    exit 1
  fi
fi

exit 0
