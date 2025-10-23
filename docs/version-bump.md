# Version Bump Guide

This guide explains the semantic versioning strategy and automated version management for the Gen3 KRO platform.

## Overview

The Gen3 KRO platform uses semantic versioning (SemVer) with automated patch version bumping. Version information is stored in the `.version` file and managed by the `version-bump.sh` script.

## Semantic Versioning

Format: `MAJOR.MINOR.PATCH`

- **MAJOR**: Incompatible API changes (manual bump)
- **MINOR**: New features, backwards-compatible (manual bump)
- **PATCH**: Bug fixes, backwards-compatible (automatic bump)

Examples:
- `0.1.0` → `0.1.1`: Bug fix
- `0.1.1` → `0.2.0`: New feature
- `0.2.0` → `1.0.0`: Breaking change

## Version File

The `.version` file at the repository root contains the current version:

```
0.3.2
```

This is the source of truth for the current version.

## Version Bump Script

Location: `scripts/version-bump.sh`

### Behavior

The script automatically handles version bumping:

1. **Read current version** from `.version` file
2. **Check latest Git tag**
3. **Determine action**:
   - If MAJOR/MINOR changed manually: Use version from file, create tag
   - If version matches latest tag: Auto-bump PATCH, create tag
   - If version already differs from tag: Create tag for current version

### Usage

```bash
./scripts/version-bump.sh
```

### Output

```
Current version in .version file: 0.3.2
Latest git tag: v0.3.2
Auto-bumping patch version: 0.3.2 → 0.3.3
Creating tag: v0.3.3
✓ Created tag: v0.3.3
NEW_VERSION=0.3.3
TAG_NAME=v0.3.3
```

## Workflows

### Automatic Patch Bump

For bug fixes and small changes:

```bash
# Make changes
vim terraform/modules/vpc/main.tf

# Commit
git add terraform/modules/vpc/main.tf
git commit -m "fix: Correct subnet tagging logic"

# Run version bump (auto-increments patch)
./scripts/version-bump.sh

# Push with tags
git push origin main --follow-tags
```

Result: `0.3.2` → `0.3.3`

### Manual Minor Bump

For new features:

```bash
# Make changes
vim terraform/modules/new-feature/

# Commit
git add terraform/modules/new-feature/
git commit -m "feat: Add new feature module"

# Update version file manually
echo "0.4.0" > .version

# Run version bump (creates tag for 0.4.0)
./scripts/version-bump.sh

# Push with tags
git push origin main --follow-tags
```

Result: `0.3.2` → `0.4.0`

### Manual Major Bump

For breaking changes:

```bash
# Make changes
vim terraform/combinations/hub/main.tf

# Commit
git add terraform/combinations/hub/main.tf
git commit -m "BREAKING CHANGE: Refactor hub module inputs"

# Update version file manually
echo "1.0.0" > .version

# Run version bump (creates tag for 1.0.0)
./scripts/version-bump.sh

# Push with tags
git push origin main --follow-tags
```

Result: `0.3.2` → `1.0.0`

## Git Tags

### Format

Tags are prefixed with `v`: `v0.3.2`, `v1.0.0`

### Viewing Tags

```bash
# List all tags
git tag

# Show latest tag
git describe --tags --abbrev=0

# Show tag details
git show v0.3.2
```

### Creating Tags Manually

```bash
# Annotated tag (recommended)
git tag -a v0.3.3 -m "Release 0.3.3"

# Lightweight tag
git tag v0.3.3

# Push tag
git push origin v0.3.3

# Push all tags
git push --tags
```

### Deleting Tags

```bash
# Delete local tag
git tag -d v0.3.3

# Delete remote tag
git push origin --delete v0.3.3
```

## CI/CD Integration

### GitHub Actions

Example workflow using version-bump.sh:

```yaml
name: Version Bump and Release

on:
  push:
    branches: [main]

jobs:
  version:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0  # Fetch all history for tags

      - name: Run Version Bump
        id: version
        run: |
          ./scripts/version-bump.sh
          echo "new_version=$(cat .version)" >> $GITHUB_OUTPUT

      - name: Push Tags
        run: |
          git push --follow-tags

      - name: Create GitHub Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          tag_name: v${{ steps.version.outputs.new_version }}
          release_name: Release ${{ steps.version.outputs.new_version }}
          draft: false
          prerelease: false
```

### GitLab CI

Example `.gitlab-ci.yml`:

```yaml
stages:
  - version
  - release

version_bump:
  stage: version
  script:
    - ./scripts/version-bump.sh
    - git push --follow-tags
  only:
    - main
```

## Release Notes

### Manual Release Notes

Create release notes in `RELEASE_NOTES_v<VERSION>.md`:

```bash
cat > RELEASE_NOTES_v0.3.3.md <<EOF
# Release Notes v0.3.3

## Bug Fixes

- Fixed subnet tagging issue in VPC module
- Corrected IAM policy attachment logic

## Improvements

- Updated ACK controller versions
- Enhanced error messages in validation scripts

## Breaking Changes

None

## Upgrade Instructions

1. Update to latest code: \`git pull origin main\`
2. Run \`terragrunt init -upgrade\`
3. Run \`terragrunt apply\`
EOF

git add RELEASE_NOTES_v0.3.3.md
git commit -m "docs: Add release notes for v0.3.3"
```

### Automated Release Notes

Use conventional commits to generate release notes:

```bash
# Install git-cliff
cargo install git-cliff

# Generate release notes
git-cliff --tag v0.3.3 > RELEASE_NOTES_v0.3.3.md
```

## Conventional Commits

Use conventional commit format for automatic categorization:

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature (minor bump)
- `fix`: Bug fix (patch bump)
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tool changes
- `BREAKING CHANGE`: Breaking changes (major bump)

### Examples

**Feature**:
```
feat(iam-policy): Add support for AWS managed policies

- Load managed policy ARNs from managed-policy-arns.txt
- Attach managed policies to pod identities
- Update documentation

Closes #42
```

**Bug Fix**:
```
fix(vpc): Correct subnet CIDR calculation

Fixed issue where private subnet CIDRs were overlapping.

Fixes #38
```

**Breaking Change**:
```
feat(hub)!: Refactor ack_configs input structure

BREAKING CHANGE: ack_configs now requires namespace and service_account
fields. Update all terragrunt.hcl files to include these fields.

Migration guide:
```hcl
# Before
ack_configs = {
  ec2 = { enable_pod_identity = true }
}

# After
ack_configs = {
  ec2 = {
    enable_pod_identity = true
    namespace           = "ack-system"
    service_account     = "ack-ec2-sa"
  }
}
```

Closes #45
```

## Version Checking

### Current Version

```bash
# Read from .version file
cat .version

# Or from Git tag
git describe --tags --abbrev=0
```

### Terraform Version

Display version in Terraform output:

```hcl
# outputs.tf
output "platform_version" {
  description = "Gen3 KRO platform version"
  value       = file("${path.root}/../../../../.version")
}
```

Query:
```bash
terragrunt output platform_version
```

### Kubernetes ConfigMap

Store version in ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-version
  namespace: kube-system
data:
  version: "0.3.3"
```

## Troubleshooting

### Tag Already Exists

**Symptom**:
```
ERROR: Tag v0.3.3 already exists!
```

**Solution**:
```bash
# Check existing tags
git tag

# If tag is incorrect, delete and recreate
git tag -d v0.3.3
git push origin --delete v0.3.3

# Update .version file
echo "0.3.4" > .version

# Run version bump again
./scripts/version-bump.sh
```

### Version Mismatch

**Symptom**: `.version` doesn't match latest tag

**Solution**:
```bash
# Check latest tag
LATEST_TAG=$(git describe --tags --abbrev=0)
echo "Latest tag: $LATEST_TAG"

# Check .version file
VERSION_FILE=$(cat .version)
echo "Version file: $VERSION_FILE"

# Sync version file to latest tag
echo "${LATEST_TAG#v}" > .version

# Or bump manually
echo "0.3.4" > .version
```

### CI/CD Push Fails

**Symptom**: CI/CD can't push tags

**Solution**: Ensure CI/CD has write permissions

GitHub Actions:
```yaml
permissions:
  contents: write
```

GitLab CI: Verify bot has Maintainer role

## Best Practices

### 1. Version Before Merging

Run version-bump.sh before merging to main:

```bash
git checkout -b feature/new-feature
# Make changes
git commit -m "feat: Add new feature"

# Bump version
./scripts/version-bump.sh

# Push
git push origin feature/new-feature
# Create PR
```

### 2. Use Conventional Commits

Consistent commit messages enable automated changelog generation:

```bash
git commit -m "fix(vpc): Correct subnet tagging"
git commit -m "feat(iam): Add managed policy support"
git commit -m "docs: Update README"
```

### 3. Document Breaking Changes

Always document breaking changes in commit body:

```bash
git commit -m "feat(hub)!: Refactor inputs

BREAKING CHANGE: Input structure changed. See migration guide.

Migration: Update ack_configs to include namespace field."
```

### 4. Tag Releases

Always tag releases:

```bash
./scripts/version-bump.sh
git push --follow-tags
```

### 5. Maintain Changelog

Keep `CHANGELOG.md` updated:

```markdown
# Changelog

## [0.3.3] - 2025-10-23

### Fixed
- VPC subnet tagging issue
- IAM policy attachment logic

### Changed
- Updated ACK controller versions
```

## See Also

- [Semantic Versioning](https://semver.org/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Git Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging)
- [scripts/version-bump.sh](../scripts/version-bump.sh)
