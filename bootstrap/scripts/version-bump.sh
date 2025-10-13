#!/usr/bin/env bash
set -euo pipefail

# scripts/version-bump.sh
# Automated semantic versioning with patch auto-increment
# Usage: ./version-bump.sh [patch|minor|major]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
VERSION_FILE="${REPO_ROOT}/.version"

# Initialize version file if it doesn't exist
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "0.0.0" > "$VERSION_FILE"
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE")
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Determine bump type (default: patch for automated CI)
BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
  patch)
    PATCH=$((PATCH + 1))
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  *)
    echo "Error: Invalid bump type. Use: patch, minor, or major"
    exit 1
    ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "$NEW_VERSION" > "$VERSION_FILE"

echo "Version bumped: ${CURRENT_VERSION} → ${NEW_VERSION} (${BUMP_TYPE})"
echo "NEW_VERSION=${NEW_VERSION}"
exit 0
