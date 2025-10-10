#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-staging}
BASE="config/base.yaml"
OVERLAY="config/environments/${ENV}.yaml"
OUTPUT="config/config.yaml"

if [[ ! -f "$BASE" ]]; then
  echo "Error: Base config not found: $BASE"
  exit 1
fi

if [[ ! -f "$OVERLAY" ]]; then
  echo "Error: Environment overlay not found: $OVERLAY"
  exit 1
fi

# Merge using yq
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
  "$BASE" "$OVERLAY" > "$OUTPUT"

echo "✓ Merged $BASE + $OVERLAY -> $OUTPUT"
