#!/usr/bin/env bash
set -euo pipefail

# CI Version Management Script
# Auto-bumps patch version if no changes to major/minor
# Creates git tags for releases
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
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
echo "Latest git tag: ${LATEST_TAG}"

# Remove 'v' prefix if present
LATEST_TAG=${LATEST_TAG#v}
IFS='.' read -r TAG_MAJOR TAG_MINOR TAG_PATCH <<< "$LATEST_TAG"

# Determine if we need to bump version
SHOULD_BUMP=false
NEW_VERSION="${CURRENT_VERSION}"

# Check if major or minor changed
if [[ "$CURRENT_MAJOR" != "$TAG_MAJOR" ]] || [[ "$CURRENT_MINOR" != "$TAG_MINOR" ]]; then
  # Major or minor changed - use version from file as-is
  echo "Major/Minor version changed. Using version from file: ${NEW_VERSION}"
  SHOULD_BUMP=true
else
  # Check if current version is same as latest tag (need to auto-bump)
  if [[ "$CURRENT_VERSION" == "$LATEST_TAG" ]]; then
    # Auto-bump patch version
    NEW_PATCH=$((CURRENT_PATCH + 1))
    NEW_VERSION="${CURRENT_MAJOR}.${CURRENT_MINOR}.${NEW_PATCH}"
    echo "Auto-bumping patch version: ${CURRENT_VERSION} → ${NEW_VERSION}"
    SHOULD_BUMP=false

    # Update version file
    echo "$NEW_VERSION" > "$VERSION_FILE"
  else
    # Version file already has a new version (manual bump)
    echo "Version file already updated: ${CURRENT_VERSION}"
    SHOULD_BUMP=true
  fi
fi

# Create git tag only if version changed
TAG_NAME="v${NEW_VERSION}"

if $SHOULD_BUMP; then
  echo "Creating tag: ${TAG_NAME}"

  if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "ERROR: Tag ${TAG_NAME} already exists!"
    echo "This should not happen - version bump logic may be incorrect."
    exit 1
  else
    git tag -a "$TAG_NAME" -m "Release ${NEW_VERSION}"
    echo "✓ Created tag: ${TAG_NAME}"
  fi
else
  echo "No version bump needed."
fi

# Output for CI/CD systems
echo "NEW_VERSION=${NEW_VERSION}"
echo "TAG_NAME=${TAG_NAME}"

exit 0
