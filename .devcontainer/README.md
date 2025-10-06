# Gen3-KRO Development Container

This directory contains the VS Code Dev Container configuration for the gen3-kro project. The dev container provides a consistent development environment across different machines (home, office, etc.) and eliminates path-related issues with WSL2 and OneDrive.

## Prerequisites

1. **Docker Desktop** with WSL2 integration enabled
2. **VS Code** with the "Dev Containers" extension installed
3. **Git** configured with SSH keys for GitHub

## What's Included

The dev container includes all necessary tools for working with gen3-kro:

- **Terraform** v1.5.7 (pinned to match `.terraform-version`)
- **Terragrunt** v0.55.1
- **kubectl** v1.31.0 (matches Kubernetes version in config)
- **Helm** v3.14.0
- **AWS CLI** v2
- **yq** v4.44.3 (YAML processor)
- **k9s** (Kubernetes CLI UI)
- **ArgoCD CLI**
- **kustomize**

## Quick Start

### First-Time Setup

1. **Clone the repository** (if not already done):
   ```bash
   cd ~/work
   git clone git@github.com:indiana-university/gen3-kro.git
   cd gen3-kro
   ```

2. **Open in VS Code**:
   ```bash
   code .
   ```

3. **Reopen in Container**:
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
   - Select: `Dev Containers: Reopen in Container`
   - Wait for the container to build (first time takes 5-10 minutes)

### Using the Dev Container

Once inside the container:

```bash
# Verify tools are installed
terraform version
terragrunt --version
kubectl version --client
aws --version

# Your workspace is at /workspaces/gen3-kro
cd /workspaces/gen3-kro

# AWS credentials are mounted from your host
aws sts get-caller-identity --profile boadeyem_tf

# Run Terragrunt commands (no path issues!)
./bootstrap/terragrunt-wrapper.sh staging validate
./bootstrap/terragrunt-wrapper.sh staging plan
```

## Mounted Directories

The following directories are mounted from your host machine:

- **Workspace**: `${localWorkspaceFolder}` → `/workspaces/gen3-kro`
- **AWS Config**: `~/.aws` → `/home/vscode/.aws`
- **Kube Config**: `~/.kube` → `/home/vscode/.kube`
- **Docker Socket**: `/var/run/docker.sock` (for Docker-in-Docker)

## Helpful Aliases

The container comes with pre-configured aliases:

- `k` → `kubectl`
- `tf` → `terraform`
- `tg` → `terragrunt`

## Benefits

### ✅ Solves Path Issues
- No more "Masters-Career Documents" path problems
- Clean Linux paths: `/workspaces/gen3-kro`
- Git and Terragrunt work reliably

### ✅ Consistent Environment
- Same tools and versions everywhere
- No "works on my machine" issues
- Automated setup for new team members

### ✅ Isolated Dependencies
- Tools installed in container, not host
- No version conflicts with other projects
- Easy to update or reset

## Troubleshooting

### Container Won't Build
```bash
# Check Docker is running
docker ps

# Rebuild without cache
Ctrl+Shift+P → Dev Containers: Rebuild Container
```

### AWS Credentials Not Working
```bash
# Verify mount exists
ls -la /home/vscode/.aws

# Check credentials file
cat /home/vscode/.aws/credentials

# Test AWS CLI
aws sts get-caller-identity --profile boadeyem_tf
```

### Git Safe Directory Warning
The `postCreateCommand` automatically adds the workspace to git's safe directories. If you still see warnings:
```bash
git config --global --add safe.directory /workspaces/gen3-kro
```

### Slow Performance
- Ensure Docker Desktop has adequate resources (Settings → Resources)
- Recommended: 4GB RAM, 2 CPUs minimum
- WSL2 integration should be enabled for your distro

## Customization

### Adding VS Code Extensions
Edit `.devcontainer/devcontainer.json`:
```json
"extensions": [
  "ms-azuretools.vscode-docker",
  "your-extension-id-here"
]
```

### Installing Additional Tools
Edit `.devcontainer/Dockerfile` and add RUN commands:
```dockerfile
RUN curl -L https://example.com/tool -o /usr/local/bin/tool \
    && chmod +x /usr/local/bin/tool
```

### Changing Tool Versions
Update the ARG variables in `Dockerfile`:
```dockerfile
ARG TERRAFORM_VERSION=1.6.0
ARG TERRAGRUNT_VERSION=0.56.0
```

## Testing the Setup

After opening in the dev container:

```bash
# 1. Verify all tools
terraform version
terragrunt --version
kubectl version --client
helm version
aws --version
yq --version

# 2. Test AWS access
aws sts get-caller-identity --profile boadeyem_tf

# 3. Run validation tests
cd /workspaces/gen3-kro
./bootstrap/terragrunt-wrapper.sh staging validate

# 4. Check git works
git status
```

## VS Code Settings

The container includes optimized VS Code settings:

- **YAML formatting** with `redhat.vscode-yaml`
- **Terraform formatting** with `hashicorp.terraform`
- **Auto-trim** trailing whitespace
- **Hide** `.terraform` and `.terragrunt-cache` directories
- **GitHub Copilot** enabled (if extension installed)

## Network Configuration

The container uses `--network=host` to:
- Access services running on WSL2
- Connect to local Kubernetes clusters
- Avoid network translation overhead

## References

- [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers)
- [Dev Container Features](https://containers.dev/features)
- [gen3-kro Documentation](../README.md)

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review Docker Desktop logs
3. Rebuild the container: `Ctrl+Shift+P` → `Dev Containers: Rebuild Container`
4. Contact the platform engineering team
