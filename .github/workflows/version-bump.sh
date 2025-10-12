#!/usr/bin/env bash
set -euo pipefail

# CI Version Management Script
# Checks if major/minor changed in .version file
# If unchanged: auto-bump patch and tag
# If changed: just tag with new version
# Usage: ./version-bump.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
VERSION_FILE="${REPO_ROOT}/.version"

# Initialize version file if it doesn't exist
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "0.0.0" > "$VERSION_FILE"
  echo "Initialized version file with 0.0.0"
fi

# Read current version from file
CURRENT_VERSION=$(cat "$VERSION_FILE")
IFS='.' read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH <<< "$CURRENT_VERSION"

echo "Current version in .version file: ${CURRENT_VERSION}"

# Get latest git tag (if exists)
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
echo "Latest git tag: ${LATEST_TAG}"

# Remove 'v' prefix if present
LATEST_TAG=${LATEST_TAG#v}
IFS='.' read -r TAG_MAJOR TAG_MINOR TAG_PATCH <<< "$LATEST_TAG"

# Check if major or minor changed
if [[ "$CURRENT_MAJOR" != "$TAG_MAJOR" ]] || [[ "$CURRENT_MINOR" != "$TAG_MINOR" ]]; then
  # Major or minor changed - use version from file as-is
  NEW_VERSION="${CURRENT_VERSION}"
  echo "Major/Minor version changed. Using version from file: ${NEW_VERSION}"
else
  # Major and minor unchanged - bump patch
  NEW_PATCH=$((CURRENT_PATCH + 1))
  NEW_VERSION="${CURRENT_MAJOR}.${CURRENT_MINOR}.${NEW_PATCH}"
  echo "Major/Minor unchanged. Auto-bumping patch: ${CURRENT_VERSION} → ${NEW_VERSION}"

  # Update version file
  echo "$NEW_VERSION" > "$VERSION_FILE"
fi

# Create git tag
TAG_NAME="v${NEW_VERSION}"
echo "Creating tag: ${TAG_NAME}"

if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  echo "Warning: Tag ${TAG_NAME} already exists. Skipping tag creation."
else
  git tag -a "$TAG_NAME" -m "Release ${NEW_VERSION}"
  echo "✓ Tagged: ${TAG_NAME}"
fi

# Output for CI/CD systems
echo "NEW_VERSION=${NEW_VERSION}"
echo "TAG_NAME=${TAG_NAME}"

exit 0
