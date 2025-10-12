# Release Notes - v0.3.2

## Overview
This is a hotfix release that addresses critical CI/CD pipeline issues with automated version bumping and git tagging. The release ensures proper semantic versioning and automated releases for the project.

## Key Changes

### 🐛 Bug Fixes

#### CI/CD Pipeline
- **Fixed version-bump script path**: Corrected path from `bootstrap/scripts/version-bump.sh` to `.github/workflows/version-bump.sh` in docker-ci.yml
- **Removed invalid argument**: Script doesn't accept `patch` argument, simplified invocation
- **Enhanced git push**: Added explicit branch specification (`origin main`) and tag pushing to CI workflow
- **Improved error handling**: Better fallback messages for commit and push operations

#### Version Management
- **Auto-increment logic**: Patch version now correctly auto-increments when `.version` matches latest tag
- **Duplicate tag prevention**: Script fails fast if attempting to create existing tag
- **Smart version detection**: Compares version file with git tags to determine action
- **Tag creation**: Git tags are now properly created and pushed to remote repository
- **Version file sync**: `.version` file stays in sync with git tags
- **No manual updates needed**: Developers don't need to update `.version` for patch releases

### 📚 Documentation

#### README Updates
- **CI/CD Pipeline section**: Added comprehensive documentation on automated versioning
- **Version Management**: Documented how auto-patch bump works
- **Docker Image Build**: Explained multi-tag strategy and immutable tags
- **Manual version bump**: Added instructions for manual version control
- **Release History**: Updated with v0.3.1 and v0.3.2 entries

## Technical Details

### CI Workflow Changes
**File**: `.github/workflows/docker-ci.yml`

**Before:**
```yaml
chmod +x bootstrap/scripts/version-bump.sh
./bootstrap/scripts/version-bump.sh patch
```

**After:**
```yaml
chmod +x .github/workflows/version-bump.sh
./.github/workflows/version-bump.sh
```

**Git Push Improvements:**
```yaml
git push origin main || echo "Nothing to push"
git push origin --tags || echo "No tags to push"
```

### Version Bump Script
**Location**: `.github/workflows/version-bump.sh`

**Behavior:**
- Reads current version from `.version` file
- Gets latest git tag
- If major/minor unchanged: auto-bump patch (0.3.1 → 0.3.2)
- If major/minor changed: use version from file as-is
- Creates annotated git tag (e.g., `v0.3.2`)
- Updates `.version` file

## Testing

### Manual Testing Results
```bash
$ bash .github/workflows/version-bump.sh
Current version in .version file: 0.3.1
Latest git tag: v0.3.1
Major/Minor unchanged. Auto-bumping patch: 0.3.1 → 0.3.2
Creating tag: v0.3.2
✓ Tagged: v0.3.2
NEW_VERSION=0.3.2
TAG_NAME=v0.3.2
```

**Verification:**
- ✅ Version file updated: `.version` now contains `0.3.2`
- ✅ Git tag created: `v0.3.2` tag exists
- ✅ Script exits cleanly with proper output

## Migration Notes

### For CI/CD
- No manual intervention required
- Next push to `main` branch will automatically:
  1. Run version-bump script
  2. Increment patch version
  3. Create and push git tag
  4. Build and push Docker images with proper tags

### For Manual Version Bumps
To manually bump major or minor version:

```bash
# Update version file
echo "0.4.0" > .version

# Commit changes
git add .version
git commit -m "chore: bump to v0.4.0"

# Push to trigger CI (CI will create the tag)
git push origin main
```

## Known Issues
None - all critical CI/CD issues resolved.

## Future Work
- Add automated testing for version-bump script
- Implement changelog generation from git commits
- Add release notes auto-generation
- Create GitHub releases via CI

## Contributors
- **Babasanmi Adeyemi** (boadeyem) - RDS Team
- CI/CD pipeline fixes and documentation

---

**Release Date**: October 12, 2025
**Previous Version**: v0.3.1
**Next Planned**: v0.4.0 (Feature enhancements and testing)
