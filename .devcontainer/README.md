# Development Container

Development container configuration for the **eks-cluster-mgmt** platform — a multi-account EKS control plane using CSOC + KRO + ACK + ArgoCD.

## Overview

```
.devcontainer/
├── devcontainer.json    # Main configuration (cross-platform)
└── README.md            # This file
```

The container is built from the root `Dockerfile` (Ubuntu 24.04) and includes all tools needed for Terraform, Kubernetes, AWS, GitOps, and MCP-based AI agent workflows.

## Security Posture

This devcontainer follows the principle of least privilege:

| Risk Area | Mitigation |
|-----------|------------|
| No `--privileged` | Removed `docker-outside-of-docker` feature that injected it |
| No Docker socket mount | Docker CLI not required by any scripts or modules |
| No `--network=host` | Replaced with scoped `forwardPorts: [8080]` for ArgoCD UI |
| `--security-opt=no-new-privileges` | Prevents SUID/SGID privilege escalation inside container |
| Scoped credential mount | Only `~/.aws/eks-devcontainer` is mounted — not all of `~/.aws` |
| `~/.kube` not mounted | Created empty at runtime; `connect` stage populates it |
| AI agent sandbox disabled | Required for agents to run terraform/kubectl/helm — the only intentional relaxation |

## Pre-installed Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | 1.13.5 | Infrastructure as code |
| Terragrunt | 0.99.1 | Terraform wrapper for DRY configurations |
| kubectl | 1.35.1 | Kubernetes CLI |
| Helm | 3.16.1 | Package manager for Kubernetes |
| AWS CLI | 2.32.0 | AWS API access |
| yq | 4.44.3 | YAML processor |
| kustomize | 5.7.1 | Kubernetes manifest customization |
| k9s | latest | Kubernetes CLI UI |
| argocd | latest | ArgoCD CLI |
| uv / uvx | 0.10.2 | Python package/tool runner (Astral) |
| Node.js + npm | system (Ubuntu 24.04) | JS runtime (required for `npx`-based MCP servers) |
| jq | system | JSON processor |
| git | latest (feature) | Version control |

Shell aliases are pre-configured: `k` → kubectl, `tf` → terraform, `tg` → terragrunt.

## Environment Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `REPO_ROOT` | `/workspaces/eks-cluster-mgmt` | Repository root inside container |
| `AWS_PROFILE` | `csoc` | AWS CLI profile selector |
| `AWS_REGION` | from `config/shared.auto.tfvars.json` | Set by `container-init.sh` at runtime |
| `AWS_DEFAULT_REGION` | same as `AWS_REGION` | Set by `container-init.sh` at runtime |
| `TF_DATA_DIR` | `/home/vscode/.terraform-data` | Redirects `.terraform/` to ext4 to avoid Windows DrvFs chmod failures |

`AWS_REGION`, `AWS_DEFAULT_REGION`, and `TF_DATA_DIR` are written to `~/.container-env` by the `setup` stage and sourced in `.bashrc` for all subsequent terminals.

## Credential Mount

The devcontainer mounts a **scoped** subdirectory — not the entire `~/.aws`:

```
Host:      ~/.aws/eks-devcontainer/   →   Container: /home/vscode/.aws/
```

This means only credentials written to `~/.aws/eks-devcontainer/` on the host are visible inside the container. Host profiles, static keys, and other credentials are never exposed.

### Cross-platform mount source

The mount source uses `${localEnv:HOME}${localEnv:USERPROFILE}` so it resolves on both Linux/macOS (`HOME`) and Windows (`USERPROFILE`):

```json
"mounts": [
  "source=${localEnv:HOME}${localEnv:USERPROFILE}/.aws/eks-devcontainer,target=/home/vscode/.aws,type=bind,consistency=cached"
]
```

### How credentials get there

Run `mfa-session.sh` **on the host** before starting (or rebuilding) the container:

```bash
# Option A — MFA (production, scoped devcontainer role):
bash scripts/mfa-session.sh <MFA_CODE>

# Option B — No MFA (trusted dev environment, admin profile):
bash scripts/mfa-session.sh --no-mfa
```

The script writes temporary credentials to `~/.aws/eks-devcontainer/credentials` under the `[csoc]` profile. The container's `AWS_PROFILE=csoc` picks them up automatically.

### Not mounted (intentionally)

| Path | Reason |
|------|--------|
| `~/.kube` | Created empty inside the container; the `connect` stage runs `aws eks update-kubeconfig` to populate it |
| `~/.azure`, `~/.config/gcloud` | Not used by this EKS-only project |

## Post-Create Lifecycle

`devcontainer.json` runs a single post-create command:

```bash
bash scripts/container-init.sh setup init apply connect
```

### Stage Reference

Each positional flag is opt-in. With no flags, the script is a safe no-op.

| Stage | What it does |
|-------|-------------|
| `setup` | Create dirs (`~/.kube`, output dirs), clean previous runs, validate AWS creds, write `~/.container-env` (sets `TF_DATA_DIR`, `AWS_REGION`, etc.), copy deploy scripts to env dir, copy `.mcp/mcp.json` → `.vscode/mcp.json`, configure Codex sandbox, mark git safe directory |
| `init` | Generate + push SSM repo secrets to AWS Secrets Manager, then run `install.sh init` (terraform init with backend config) |
| `apply` | Run `install.sh apply` (terraform apply + connect to cluster) |
| `connect` | Read `config/shared.auto.tfvars.json` for cluster name/region, run `aws eks update-kubeconfig`, retrieve ArgoCD admin password, start `kubectl port-forward` for ArgoCD UI on port 8080 |

### Common stage combinations

```jsonc
// devcontainer.json → postCreateCommand examples:

// Dev: environment setup only (no Terraform)
"bash scripts/container-init.sh setup"

// Dev: setup + connect to an existing cluster (no Terraform)
"bash scripts/container-init.sh setup connect"

// CI / Fresh deploy: full pipeline
"bash scripts/container-init.sh setup init apply connect"

// Re-apply after setup was already done
"bash scripts/container-init.sh init apply"
```

All stages log to `outputs/logs/container-init-<timestamp>.log`.

## Config Source of Truth

All user-editable configuration lives in `config/shared.auto.tfvars.json`. This file drives:

- Terraform variables (auto-loaded by filename convention)
- `install.sh` / `destroy.sh` backend config extraction
- `container-init.sh` cluster name + region resolution (for the `connect` stage)

Copy from the example and populate before first use:

```bash
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json
# Edit with your account IDs, cluster name, region, etc.
```

## Usage

### Prerequisites

1. [Visual Studio Code](https://code.visualstudio.com/)
2. [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.ms-vscode-remote.remote-containers)
3. [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or compatible runtime)
4. [WSL](https://docs.microsoft.com/en-us/windows/wsl/install) (Windows only)
5. Repository cloned to a **native Linux filesystem** (WSL ext4, not `/mnt/c/...`) so `chmod` works in the container

### First-Time Setup

```bash
# 1. Clone the repo (inside WSL on Windows)
git clone <repo-url> ~/src/eks-cluster-mgmt
cd ~/src/eks-cluster-mgmt

# 2. Copy and populate config
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json

# 3. (If using developer-identity module for first time)
#    cd terraform/env/developer-identity && terraform apply
#    Register MFA device per outputs/mfa-setup-instructions.txt

# 4. Authenticate on the HOST
bash scripts/mfa-session.sh <MFA_CODE>     # or: --no-mfa

# 5. Open in VS Code → "Reopen in Container"
code .
```

### Day-to-Day

```bash
# Re-authenticate (on HOST, when credentials expire)
bash scripts/mfa-session.sh <MFA_CODE>

# Inside the container — plan changes
bash scripts/install.sh plan

# Inside the container — apply changes
bash scripts/install.sh apply

# Inside the container — destroy stack
bash scripts/destroy.sh

# Reconnect to cluster (after container restart)
bash scripts/container-init.sh connect

# Validate Helm charts
helm template argocd/charts/application-sets/
helm template argocd/charts/instances/
helm template argocd/charts/resource-groups/
```

> **Important:** Always use `install.sh` / `destroy.sh` for Terraform operations — never run `terraform init/plan/apply/destroy` directly.

### ArgoCD UI

After the `connect` stage completes, the ArgoCD UI is available at:

```
https://localhost:8080
Username: admin
Password: (see outputs/argocd-password.txt)
```

Port 8080 is forwarded from container to host via `forwardPorts`.

## VS Code Extensions

| Extension | Purpose |
|-----------|---------|
| `hashicorp.terraform` | Terraform syntax, validation, formatting |
| `ms-kubernetes-tools.vscode-kubernetes-tools` | Kubernetes resource explorer |
| `redhat.vscode-yaml` | YAML schema validation |
| `github.copilot-chat` | AI-assisted coding |
| `openai.chatgpt` | AI-assisted coding |
| `4ops.terraform` | Terragrunt linting |

## VS Code Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `terminal.integrated.defaultProfile.linux` | `bash` | Default shell |
| `chat.tools.terminal.sandbox.enabled` | `false` | Allow AI agents to run infra commands |
| `editor.tabSize` | `2` | Project convention |
| `files.trimTrailingWhitespace` | `true` | Clean whitespace |
| `files.insertFinalNewline` | `true` | POSIX compliance |
| `files.associations: *.hcl` | `terragrunt` | Syntax highlighting for `.hcl` files |

## Troubleshooting

### AWS credentials not found

```
WARNING: ~/.aws/credentials not found.
```

Run `mfa-session.sh` on the **host** before starting the container. The script writes to `~/.aws/eks-devcontainer/credentials`, which the container bind-mounts.

### Permission / chmod errors on Terraform init

`TF_DATA_DIR` is set to `/home/vscode/.terraform-data` (container-local ext4) to avoid `chmod`/`rename` failures when the workspace is on a Windows DrvFs bind-mount. If you still see errors, ensure the repo is cloned to a native Linux filesystem (WSL ext4), not `/mnt/c/...`.

### Container build failures

```bash
# Clean Docker cache
docker builder prune

# Rebuild without cache (run from repo root)
docker build --no-cache -f Dockerfile .
```

### Port 8080 already in use

The `connect` stage kills existing listeners on port 8080 before starting the port-forward. If it still fails, manually kill the process:

```bash
lsof -ti:8080 | xargs kill -9 2>/dev/null
```

### Cluster not reachable after container restart

Re-run the connect stage to refresh kubeconfig and restart the port-forward:

```bash
bash scripts/container-init.sh connect
```

### VS Code Extension Issues

1. Uninstall problematic extension
2. Rebuild container: F1 → "Dev Containers: Rebuild Container"
3. Reinstall extension within container


See [`docs/guides/setup.md`](../docs/guides/setup.md) for detailed first-time setup instructions.

---
**Last updated:** 2025-10-28
