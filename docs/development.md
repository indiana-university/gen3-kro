# Development Guide

This guide covers development workflows, testing, and contribution guidelines.

## Development Environment

### Prerequisites

- Docker Desktop or Podman
- VS Code with Dev Containers extension
- Git
- AWS CLI (for testing)

### Dev Container Setup

This repository includes a complete dev container configuration.

**Open in Dev Container**:
1. Open repository in VS Code
2. Press `F1` → "Dev Containers: Reopen in Container"
3. Container builds with all tools pre-installed

**Included Tools**:
- Terraform 1.5.0+
- Terragrunt 0.55.0+
- kubectl 1.31.0+
- aws-cli 2.x
- yq
- kustomize
- helm
- argocd CLI

### Manual Setup (Without Dev Container)

```bash
# Install Terraform
wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform_1.9.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Install Terragrunt
wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.55.0/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install yq
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x yq_linux_amd64
sudo mv yq_linux_amd64 /usr/local/bin/yq
```

## Project Structure

```
gen3-kro/
├── hub/                    # Hub cluster GitOps configs
│   └── argocd/
│       ├── bootstrap/      # ArgoCD app-of-apps
│       ├── addons/         # Platform addons
│       └── fleet/          # Spoke fleet management
├── spokes/
│   └── spoke-template/     # Template for new spokes
├── shared/
│   └── kro-rgds/           # Reusable KRO ResourceGraphDefinitions
├── config/
│   ├── config.yaml         # Main configuration
│   ├── environments/       # Environment overlays
│   └── spokes/             # Spoke configurations
├── terraform/
│   ├── live/               # Terragrunt environments
│   │   └── staging/
│   └── modules/            # Terraform modules
├── bootstrap/
│   ├── terragrunt-wrapper.sh   # Main deployment script
│   └── scripts/                # Helper scripts
└── docs/                   # Documentation
```

## Common Development Tasks

### Add a New Terraform Module

1. Create module directory:
```bash
mkdir -p terraform/modules/my-module
```

2. Create module files:
```hcl
# terraform/modules/my-module/main.tf
resource "aws_example" "this" {
  name = var.name
}

# terraform/modules/my-module/variables.tf
variable "name" {
  description = "Resource name"
  type        = string
}

# terraform/modules/my-module/outputs.tf
output "id" {
  description = "Resource ID"
  value       = aws_example.this.id
}
```

3. Use in environment:
```hcl
# terraform/live/staging/my-resource/terragrunt.hcl
terraform {
  source = "../../../../modules//my-module"
}

inputs = {
  name = "my-resource-staging"
}
```

### Create a New KRO ResourceGraphDefinition

1. Create RGD file:
```bash
vim shared/kro-rgds/aws/my-resource.yaml
```

2. Define RGD:
```yaml
apiVersion: kro.run/v1alpha1
kind: ResourceGraphDefinition
metadata:
  name: myresource
spec:
  schema:
    apiVersion: v1alpha1
    kind: MyResource
    spec:
      resourceName: string

  resources:
    - id: example-resource
      template:
        apiVersion: example.services.k8s.aws/v1alpha1
        kind: ExampleResource
        metadata:
          name: ${schema.spec.resourceName}
        spec:
          name: ${schema.spec.resourceName}
```

3. Add to shared library deployment:
```yaml
# hub/argocd/addons/kro-rgds/kustomization.yaml
resources:
  - ../../../../shared/kro-rgds/aws/my-resource.yaml
```

4. Test locally:
```bash
kubectl apply --dry-run=client -f shared/kro-rgds/aws/my-resource.yaml
```

### Add a Hub Addon

1. Create addon directory:
```bash
mkdir -p hub/argocd/addons/my-addon/base
```

2. Create kustomization:
```yaml
# hub/argocd/addons/my-addon/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

helmCharts:
  - name: my-addon
    repo: https://charts.example.com
    version: 1.0.0
    releaseName: my-addon
    namespace: my-addon
    valuesFile: values.yaml
```

3. Create Application manifest:
```yaml
# hub/argocd/addons/my-addon/application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-addon
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/infrastructure
    targetRevision: main
    path: hub/argocd/addons/my-addon/base
  destination:
    server: https://kubernetes.default.svc
    namespace: my-addon
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

4. Reference in hub-addons app-of-apps:
```yaml
# hub/argocd/bootstrap/hub-addons.yaml
resources:
  - ../addons/my-addon/application.yaml
```

### Create Spoke Instance from Template

1. Create spoke config:
```bash
cp config/spokes/template.yaml config/spokes/my-team-staging.yaml
```

2. Edit configuration:
```yaml
name: my-team-staging
aws_account_id: "123456789012"
aws_region: us-west-2
environment: staging

cluster:
  name: my-team-staging-cluster
  version: "1.33"

network:
  vpc_cidr: "10.5.0.0/16"
  # ... more config
```

3. Test configuration:
```bash
# Validate YAML syntax
yq eval config/spokes/my-team-staging.yaml

# Dry-run kustomize build
kubectl kustomize --dry-run spokes/spoke-template/infrastructure/base
```

4. Commit and push:
```bash
git add config/spokes/my-team-staging.yaml
git commit -m "Add spoke: my-team-staging"
git push origin main
```

## Testing

### Validate Configuration

```bash
# Validate main config
./bootstrap/terragrunt-wrapper.sh staging validate

# Check YAML syntax
yq eval config/config.yaml
yq eval config/environments/staging.yaml
```

### Test Terraform Changes

```bash
# Plan only (no apply)
./bootstrap/terragrunt-wrapper.sh staging plan

# Review plan output
cat terraform/live/staging/tfplan.txt

# Validate specific module
cd terraform/modules/my-module
terraform init
terraform validate
```

### Test Kustomize Builds

```bash
# Hub bootstrap
kubectl kustomize hub/argocd/bootstrap/overlays/staging

# Hub addons
kubectl kustomize hub/argocd/addons/kro-controller/base

# Spoke template
kubectl kustomize spokes/spoke-template/infrastructure/base
```

### Test KRO RGDs

```bash
# Validate RGD syntax
kubectl apply --dry-run=client -f shared/kro-rgds/aws/ekscluster.yaml

# Apply to test cluster
kubectl apply -f shared/kro-rgds/aws/ekscluster.yaml

# Check RGD registered
kubectl get resourcegraphdefinitions

# Create test instance
kubectl apply -f - <<EOF
apiVersion: kro.run/v1alpha1
kind: EKSCluster
metadata:
  name: test-cluster
spec:
  clusterName: test-cluster
  version: "1.33"
  vpcCIDR: "10.99.0.0/16"
EOF

# Check status
kubectl describe ekscluster test-cluster

# Clean up
kubectl delete ekscluster test-cluster
```

### Integration Testing

```bash
# Deploy to staging
./bootstrap/terragrunt-wrapper.sh staging apply

# Wait for cluster ready
./bootstrap/scripts/connect-cluster.sh staging

# Check ArgoCD
kubectl get applications -n argocd

# Check KRO
kubectl get resourcegraphdefinitions
kubectl get pods -n kro-system

# Deploy test spoke
kubectl apply -f config/spokes/test-spoke.yaml

# Monitor spoke creation
kubectl get ekscluster test-spoke-cluster -w
```

## Troubleshooting

### Terragrunt Issues

**Clear cache**:
```bash
rm -rf terraform/live/staging/.terragrunt-cache
./bootstrap/terragrunt-wrapper.sh staging plan
```

**Debug mode**:
```bash
export TF_LOG=DEBUG
./bootstrap/terragrunt-wrapper.sh staging plan
```

**Check specific module**:
```bash
cd terraform/live/staging
terragrunt run-all plan --terragrunt-modules-that-include eks
```

### ArgoCD Issues

**Force sync**:
```bash
argocd app sync my-app --force

# Or via kubectl
kubectl patch application my-app -n argocd \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"main"}}}' \
  --type merge
```

**Check sync status**:
```bash
kubectl get application my-app -n argocd -o yaml
```

**Logs**:
```bash
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-server
```

### KRO Issues

**Check controller**:
```bash
kubectl get pods -n kro-system
kubectl logs -n kro-system deployment/kro-controller-manager
```

**Check resource status**:
```bash
kubectl describe ekscluster my-cluster
kubectl get events --field-selector involvedObject.name=my-cluster
```

**Check generated resources**:
```bash
# Resources created by KRO have labels
kubectl get all -l kro.run/graph=my-cluster
```

## Git Workflow

### Branch Strategy

```
main
 ├── feature/add-spoke-template
 ├── fix/terragrunt-wrapper-bug
 └── docs/update-architecture
```

**Branch Naming**:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring

### Commit Messages

Follow conventional commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `refactor`: Code refactoring
- `test`: Testing
- `chore`: Maintenance

**Examples**:
```
feat(kro): add EFS storage ResourceGraphDefinition

Add RGD for creating EFS filesystems with mount targets
across availability zones.

Closes #123

---

fix(terragrunt): handle missing yq gracefully

Fallback to python yaml parsing when yq is not available.

---

docs(architecture): update hub-spoke diagram

Add detailed network architecture section with VPC layout
and subnet breakdown.
```

### Pull Request Process

1. **Create branch**:
```bash
git checkout -b feature/my-feature
```

2. **Make changes**:
```bash
# Edit files
git add .
git commit -m "feat(scope): description"
```

3. **Push**:
```bash
git push origin feature/my-feature
```

4. **Open PR**:
- Use PR template
- Link related issues
- Request reviews

5. **Address feedback**:
```bash
git commit --amend  # For small changes
git push --force-with-lease
```

6. **Merge**:
- Squash and merge (preferred)
- Rebase and merge (for clean history)

## Code Style

### Terraform

**Use consistent formatting**:
```bash
terraform fmt -recursive terraform/
```

**Variable ordering**:
1. Required variables
2. Optional variables with defaults

**Resource naming**:
```hcl
# Good
resource "aws_vpc" "this" { }

# Avoid multiple resources of same type
resource "aws_vpc" "hub" { }
resource "aws_vpc" "spoke" { }
```

### YAML/Kubernetes Manifests

**Use consistent indentation** (2 spaces):
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: example
  namespace: default
data:
  key: value
```

**Order metadata fields**:
1. apiVersion
2. kind
3. metadata
4. spec

### Shell Scripts

**Follow preamble**:
```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Script description
# Usage: script.sh <arg1> <arg2>
```

**Use logging functions**:
```bash
source "$(dirname "$0")/lib-logging.sh"

log_info "Starting process"
log_warn "Potential issue detected"
log_error "Failed to complete"
```

## Documentation

### Update Documentation

When making changes, update relevant docs:

- **README.md**: High-level overview
- **docs/architecture.md**: Architecture changes
- **docs/configuration.md**: Config changes
- **docs/deployment/**: Deployment procedures

### Generate Documentation

```bash
# Generate Terraform docs (if terraform-docs installed)
terraform-docs markdown table terraform/modules/eks-hub > terraform/modules/eks-hub/README.md
```

## Release Process

### Version Bump

```bash
# Update version
./bootstrap/scripts/version-bump.sh patch  # 0.1.0 -> 0.1.1
./bootstrap/scripts/version-bump.sh minor  # 0.1.1 -> 0.2.0
./bootstrap/scripts/version-bump.sh major  # 0.2.0 -> 1.0.0
```

### Create Release

```bash
# Tag release
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0

# GitHub will trigger release workflow
```

### Changelog

Update `CHANGELOG.md`:
```markdown
## [0.1.0] - 2025-01-15

### Added
- Hub-spoke architecture
- KRO ResourceGraphDefinitions library
- Spoke fleet management via ArgoCD

### Changed
- Migrated from monorepo to hub-spoke structure

### Fixed
- Terragrunt wrapper validation logic
```

## CI/CD

### GitHub Actions (Planned)

```yaml
# .github/workflows/validate.yml
name: Validate
on: [pull_request]
jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Terraform Validate
        run: ./bootstrap/terragrunt-wrapper.sh staging validate

  kustomize:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Kustomize Build
        run: kubectl kustomize hub/argocd/bootstrap/overlays/staging
```

## Support

### Getting Help

- **Documentation**: Check docs/ folder first
- **Issues**: Open GitHub issue with template
- **Discussions**: Use GitHub Discussions for questions

### Reporting Bugs

Include:
1. Steps to reproduce
2. Expected behavior
3. Actual behavior
4. Environment (OS, versions)
5. Relevant logs

## Contributing

We welcome contributions! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

### Contribution Checklist

- [ ] Code follows style guidelines
- [ ] Tests pass
- [ ] Documentation updated
- [ ] Commit messages follow convention
- [ ] PR description is clear

## References

- [Terraform Style Guide](https://www.terraform-best-practices.com/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Conventional Commits](https://www.conventionalcommits.org/)
