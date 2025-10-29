# Contribution Guidelines

Guidelines for contributing to Gen3-KRO, including branching conventions, code quality standards, pull request requirements, and documentation policy.

## Getting Started

1. **Fork the repository**: Create a personal fork of `gen3-kro`
2. **Clone your fork**:
```bash
git clone https://github.com/<your-username>/gen3-kro.git
cd gen3-kro
```
3. **Set up remote**:
```bash
git remote add upstream https://github.com/indiana-university/gen3-kro.git
```
4. **Launch devcontainer**: Follow [setup guide](setup.md) to start development environment

## Code Quality Standards

### Terraform

**Formatting:**
```bash
terraform fmt -recursive terraform/
```

**Style guidelines:**
- Use lowercase resource names with hyphens: `aws-vpc/main.tf`
- Group related resources with comments
- Define variables with descriptions and types, but no default values

**Module documentation and template:**
See [`terraform/catalog/modules/README.md`](../terraform/catalog/modules/README.md) for the standard module template, required files, and authoring guidelines.

### YAML (ArgoCD, Kubernetes)

**Style guidelines:**
- Use 2-space indentation
- Quote string values that may be interpreted as numbers/booleans
- Include comments explaining complex configurations

### Shell Scripts

**Linting:**
```bash
shellcheck scripts/*.sh
```

**Style guidelines:**
- Enable strict mode: `set -euo pipefail`
- Source logging library: `source lib-logging.sh`
- Use `log_info`, `log_warn`, `log_error` for output
- Include usage function with examples
- Document destructive operations

See [`scripts/README.md`](../scripts/README.md) for authoring rules.

## Testing Requirements

### Pre-Commit Checks

Before committing, run:

```bash
# Format Terraform
terraform fmt -recursive terraform/

# Format Terragrunt
terragrunt hcl format

# Lint shell scripts
shellcheck scripts/*.sh
```

### Integration Testing

For infrastructure changes:

1. **Deploy to dev cluster** (example using `<csoc_alias>` environment):
```bash
   cd live/<provider>/<region>/<csoc_alias>
   terragrunt plan --all
   terragrunt apply --all
```

2. **Verify resources**:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
argocd app list
```

3. **Test functionality**:
   - Create test resources using new modules
   - Verify ArgoCD syncs new addons
   - Check IAM permissions load and work as expected

4. **Document test results** in PR description

**Note:** Environment names like `<csoc_alias>` are examples. Use your actual development environment.

## Pull Request Checklist

Before submitting a pull request:

- [ ] Branch is up-to-date with upstream `main`
- [ ] Code follows style guidelines
- [ ] All tests pass
- [ ] New modules include complete documentation (README.md with standard template)
- [ ] IAM policies added for new services (in `iam/<provider>/_default/<service>/`)
- [ ] Changes tested in dev cluster
- [ ] Commit messages follow conventional commits format
- [ ] PR description includes:
  - **Summary** of changes
  - **Motivation** for changes
  - **Testing** performed
  - **Breaking changes** (if any)

### PR Template

## Summary
Brief description of changes.

## Motivation
Why is this change needed? What problem does it solve?

## Changes
- Added X module for Y functionality
- Updated Z configuration to support A
- Fixed B issue in C component

## Testing
- [ ] Deployed to dev cluster
- [ ] Verified resource creation
- [ ] Tested ArgoCD sync
- [ ] Checked application health

## Breaking Changes
- None

## Related Issues
Closes #123

## Code Review Process

1. **Automated checks**: GitHub Actions runs linting and validation
2. **Reviewer assignment**: Maintainers review PR
3. **Feedback**: Address review comments
4. **Approval**: At least one maintainer approval required
5. **Merge**: Squash and merge to `testing-fork/<branch-name>`

**Review criteria:**
- Code quality and adherence to standards
- Test coverage and validation
- Documentation completeness
- Security implications (IAM policies, secrets handling)
- Backward compatibility

## Documentation Updates

### Documentation Standards

**README files:**
- Include "Last updated" date at bottom
- Use relative links for internal references: `[terraform](../terraform/README.md)`
- Provide code examples with syntax highlighting
- Keep language concise and actionable

**Module documentation:**
- Follow template in [`terraform/catalog/modules/README.md`](../terraform/catalog/modules/README.md)
- Include complete input/output tables
- Provide usage examples with real values
- Document lifecycle considerations and known limitations

**User guides:**
- Target audience: developers with basic cloud/Kubernetes knowledge
- Include step-by-step instructions with commands
- Provide troubleshooting sections for common errors
- Use callout blocks for warnings and important notes

### Documentation Review

Documentation changes require:
- [ ] Spelling and grammar check
- [ ] Link validation (all relative links work)
- [ ] Code example validation (examples are runnable)
- [ ] Consistency with existing docs (terminology, formatting)

## Release Process

Releases are managed by maintainers using semantic versioning.

### Version Bumping

Use the version bump script:

```bash
./scripts/version-bump.sh [major|minor|patch]
```

This updates:
- Addon versions in `argocd/addons/csoc/catalog.yaml`
- Helm chart versions in `argocd/charts/*/Chart.yaml`
- Creates git tag

### Release Checklist

- [ ] All PRs for milestone merged
- [ ] Integration tests pass
- [ ] Documentation updated
- [ ] Version bumped with appropriate level (major/minor/patch)
- [ ] RELEASE_NOTES updated
- [ ] Git tag created and pushed
- [ ] GitHub release published

## Security Considerations

### Secrets Handling

**Never commit secrets to Git:**
- `/../secrets.yaml` is gitignored
- `/../credentials/` is gitignored
- we will introduce cloud secret managers (AWS Secrets Manager, Azure Key Vault) soon for proper secrets management

### Dependency Updates

When updating dependencies:
- Review changelogs for breaking changes
- Test in dev cluster before merging
- Update version constraints in `versions.tf`

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: File a GitHub Issue with reproduction steps
- **Feature requests**: Open a GitHub Issue with use case description
- **Security issues**: Email security@uchicago.edu (do not file public issue)

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see [LICENSE](../LICENSE)).

---
**Last updated:** 2025-10-28
