# Release Checklist for v0.1.0

## Pre-Release Validation ✓

- [x] Sanitize repository (remove sensitive data)
- [x] Test terraform validation
- [x] Test terraform plan
- [x] Update documentation
- [x] Move third-party licenses
- [x] Create comprehensive docs (architecture, deployment, configuration, development)
- [x] Update .version to 0.1.0
- [x] Create CHANGELOG.md
- [x] Replace README with sanitized version
- [x] Commit changes with generic message
- [x] Create git tag v0.1.0

## Manual Steps Required

### 1. Docker Image Build & Push

**On machine with Docker access**:

```bash
# Set Docker credentials (if pushing)
export DOCKER_USERNAME=your-dockerhub-username
export DOCKER_PASSWORD=your-dockerhub-token
export DOCKER_PUSH=true
export DOCKER_TAG_LATEST=true

# Build and push
./bootstrap/scripts/docker-build-push.sh
```

**Expected output**:
```
[docker-build-push] Repository: jayadeyem/gen3-kro
[docker-build-push] Tag: v0.1.0-20251008-g<sha>
[docker-build-push] Building image...
[docker-build-push] Pushing jayadeyem/gen3-kro:v0.1.0-20251008-g<sha>
[docker-build-push] Tagging and pushing :latest
```

### 2. Push to GitHub

```bash
# Push commits
git push origin refactor-terragrunt

# Push tag
git push origin v0.1.0
```

### 3. Create GitHub Release

Go to: https://github.com/indiana-university/gen3-kro/releases/new

**Release Details**:
- **Tag**: v0.1.0
- **Title**: v0.1.0 - Hub-Spoke Architecture
- **Description**: (Use content from CHANGELOG.md [0.1.0] section)

**Release Assets**:
- Source code (automatic)
- Docker image: `jayadeyem/gen3-kro:v0.1.0-<date>-g<sha>`

### 4. Test Infrastructure Deployment (Optional but Recommended)

If you want to validate the staging infrastructure fully:

```bash
# Apply infrastructure
./bootstrap/terragrunt-wrapper.sh staging apply

# Connect to cluster
./bootstrap/scripts/connect-cluster.sh staging

# Verify ArgoCD
kubectl get applications -n argocd

# Verify KRO
kubectl get resourcegraphdefinitions
kubectl get pods -n kro-system

# Clean up (if desired)
./bootstrap/terragrunt-wrapper.sh staging destroy
```

### 5. Announcement (Optional)

Update team/users:
- Internal wiki
- Slack/Teams channel
- Email distribution list

## Post-Release

- [ ] Update project board
- [ ] Close related issues/PRs
- [ ] Archive old documentation
- [ ] Plan next release (v0.2.0 roadmap)

## Validation Tests

### Configuration
```bash
# Verify no sensitive data
grep -r "859011005590" .
grep -r "111111111111" . --exclude-dir=.git --exclude="*.md"

# Should return nothing or only placeholder examples in docs
```

### Build
```bash
# Verify version
cat .version
# Expected: 0.1.0

# Verify tag
git tag -l v0.1.0
# Expected: v0.1.0

# Verify changelog
grep "0.1.0" CHANGELOG.md
# Should exist
```

### Documentation
```bash
# Verify docs exist
ls docs/
# Expected: architecture.md, configuration.md, deployment/, development.md

# Verify README updated
head -n 5 README.md
# Should show new title: "# gen3-kro: Multi-Account EKS Platform"
```

## Rollback Plan

If issues are discovered post-release:

```bash
# Remove tag
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0

# Revert commit
git revert HEAD

# Push fix
git push origin refactor-terragrunt

# Create patch release v0.1.1
```

## Notes

- ✅ All sensitive data removed (account IDs sanitized)
- ✅ Commit message kept generic per requirements
- ✅ Documentation uses placeholder account IDs only
- ✅ Third-party licenses properly attributed
- ⚠️ Docker build requires host machine access
- ⚠️ GitHub release requires web UI or gh CLI

## Success Criteria

Release is successful when:
- [x] Tag v0.1.0 exists
- [x] Changelog complete
- [x] Documentation comprehensive
- [ ] Docker image pushed to registry
- [ ] GitHub release published
- [ ] No sensitive data in repository
