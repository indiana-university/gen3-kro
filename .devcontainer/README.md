# Development Container

Development container configuration for standardized Gen3-KRO development environments with pre-installed tools and cloud provider CLIs.

## Overview

The `.devcontainer` directory contains VS Code development container configurations that provide a consistent development environment across platforms. It uses the root Dockerfile for building the container image, installing all necessary dependencies and tools.

```
.devcontainer/
├── devcontainer.json         # Main configuration for Windows
├── devcontainer-json.unix    # Linux/macOS configuration
└── README.md                 # Documentation
```

## Container Configuration

### Base Environment

- **OS**: Ubuntu 24.04 LTS
- **User**: `vscode` (non-root)
- **Workspace**: `/workspaces/gen3-kro`

### Pre-installed Tools

| Tool | Purpose |
|------|---------|
| Terraform | Infrastructure as code |
| Terragrunt | Terraform wrapper for DRY configurations |
| kubectl | Kubernetes CLI |
| argocd | ArgoCD CLI |
| helm | Package manager for Kubernetes |
| aws | AWS CLI v2 |
| az | Azure CLI |
| gcloud | Google Cloud SDK |
| docker | Docker CLI (Docker-outside-of-Docker) |
| git | Git CLI (latest from source) |
| jq, yq | JSON/YAML processors |

### VS Code Extensions

| Extension ID | Purpose |
|-------------|---------|
| `hashicorp.terraform` | Terraform syntax highlighting, validation |
| `redhat.vscode-yaml` | YAML schema validation |
| `GitHub.copilot` | AI-assisted coding |
| `GitHub.copilot-chat` | Interactive AI assistance |
| `openai.chatgpt` | AI-assisted coding |
| `4ops.terraform` | Terragrunt linting |

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KUBECONFIG` | Kubernetes config path | `/home/vscode/.kube/config` |

## Credential Mounts

The devcontainer automatically mounts cloud provider credentials from the host machine:

### Linux/macOS Mounts

```json
"mounts": [
  "source=${localEnv:HOME}/.kube,target=/home/vscode/.kube,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.aws,target=/home/vscode/.aws,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.azure,target=/home/vscode/.azure,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.config/gcloud,target=/home/vscode/.config/gcloud,type=bind,consistency=cached"
]
```

### Windows Paths

```json
"mounts": [
  "source=${localEnv:USERPROFILE}/.kube,target=/home/vscode/.kube,type=bind",
  "source=${localEnv:USERPROFILE}/.aws,target=/home/vscode/.aws,type=bind",
  "source=${localEnv:USERPROFILE}/.azure,target=/home/vscode/.azure,type=bind",
  "source=${localEnv:USERPROFILE}/.config/gcloud,target=/home/vscode/.config/gcloud,type=bind"
]
```

## Post-Create Commands

The container executes these tasks after creation:

1. Fix workspace permissions:
   ```bash
   sudo chown -R vscode:vscode /workspaces
   ```

2. Configure Git workspace safety:
   ```bash
   git config --global --add safe.directory /workspaces
   ```

3. Create output directories:
   ```bash
   mkdir -p /workspaces/outputs/logs
   mkdir -p /workspaces/outputs/argo
   ```

4. Auto-connect to Kubernetes cluster (if credentials exist):
   ```bash
   /workspaces/scripts/connect-cluster.sh
   ```

## Usage

### Initial Setup

1. Install VS Code prerequisites:
   - [Visual Studio Code](https://code.visualstudio.com/)
   - [Remote Development Extension Pack](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack)
   - [Docker Desktop](https://www.docker.com/products/docker-desktop/)
   - [WSL (Windows Subsystem for Linux, if using Windows)](https://docs.microsoft.com/en-us/windows/wsl/install)

2. Clone repository and open in VS Code:
   ```bash
   git clone https://github.com/uc-cdis/gen3-kro.git
   cd gen3-kro
   code .
   ```

3. Click "Reopen in Container" when prompted or:
   - Press F1/Ctrl+Shift+P
   - Select "Dev Containers: Reopen in Container"
   - Wait for container build and extension installation

### Common Tasks


## Customization

### Adding Tools

Edit the Dockerfile referenced in `devcontainer.json`:

```dockerfile
# Install additional packages
RUN apt-get update && apt-get install -y \
    new-package-name

# Or use custom install scripts
COPY scripts/install-tool.sh /tmp/
RUN bash /tmp/install-tool.sh
```

### Modifying VS Code Settings

Edit the `settings` block in `devcontainer.json`:

```json
"settings": {
  "editor.tabSize": 2,
  "files.associations": {
    "*.hcl": "terragrunt"
  }
}
```

### Adding Extensions

Edit the `extensions` array in `devcontainer.json`:

```json
"extensions": [
  "hashicorp.terraform",
  "new.extension-id"
]
```

## Troubleshooting

### Permission Denied Errors

```bash
# Fix workspace permissions
sudo chown -R vscode:vscode /workspaces

# Check mounted credentials
ls -la ~/.aws ~/.kube ~/.azure ~/.config/gcloud
```

### Container Build Failures

```bash
# Clean Docker cache
docker builder prune

# Rebuild without cache
docker build --no-cache .
```

### VS Code Extension Issues

1. Uninstall problematic extension
2. Rebuild container: F1 → "Dev Containers: Rebuild Container"
3. Reinstall extension within container


See [`docs/guides/setup.md`](../docs/guides/setup.md) for detailed first-time setup instructions.

---
**Last updated:** 2025-10-26
