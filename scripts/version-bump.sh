#!/usr/bin/env bash
set -euo pipefail

# CI Version Management Script
# Auto-bumps patch version only when needed
# Creates git tags for releases
# Usage: ./version-bump.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
VERSION_FILE="${REPO_ROOT}/.version"

# Parse simple flags
DRY_RUN=0
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --help|-h)
      echo "Usage: $(basename "$0") [--dry-run]"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

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

# Check if major or minor changed from latest tag
if [[ "$CURRENT_MAJOR" != "$TAG_MAJOR" ]] || [[ "$CURRENT_MINOR" != "$TAG_MINOR" ]]; then
  # Major or minor changed - use version from file as-is and create tag
  echo "Major/Minor version changed. Using version from file: ${NEW_VERSION}"
  SHOULD_BUMP=true
elif [[ "$CURRENT_VERSION" == "$LATEST_TAG" ]]; then
  # Version file matches latest tag - auto-bump patch
  NEW_PATCH=$((CURRENT_PATCH + 1))
  NEW_VERSION="${CURRENT_MAJOR}.${CURRENT_MINOR}.${NEW_PATCH}"
  echo "Auto-bumping patch version: ${CURRENT_VERSION} → ${NEW_VERSION}"

  # Update version file
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: would update $VERSION_FILE to ${NEW_VERSION}"
  else
    echo "$NEW_VERSION" > "$VERSION_FILE"
  fi
  SHOULD_BUMP=true
else
  # Version file already has a different version than latest tag
  # This means version was manually bumped - just create the tag
  echo "Version file already updated to ${CURRENT_VERSION}, different from tag ${LATEST_TAG}"
  SHOULD_BUMP=true
fi

# Create git tag only if version changed
TAG_NAME="v${NEW_VERSION}"

if $SHOULD_BUMP; then
  echo "Creating tag: ${TAG_NAME}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: would create git tag: ${TAG_NAME}"
  else
    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
      echo "ERROR: Tag ${TAG_NAME} already exists!"
      echo "Version in .version file may need manual correction."
      exit 1
    else
      git tag -a "$TAG_NAME" -m "Release ${NEW_VERSION}"
      echo "✓ Created tag: ${TAG_NAME}"
    fi
  fi
else
  echo "No version bump needed - version unchanged."
fi

# Output for CI/CD systems
echo "NEW_VERSION=${NEW_VERSION}"
echo "TAG_NAME=${TAG_NAME}"

exit 0
