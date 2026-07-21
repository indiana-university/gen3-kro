# Development Container

Development container configuration for the **eks-cluster-mgmt** platform — a multi-account EKS control plane using CSOC + KRO + ACK + ArgoCD.

## Overview

```
.devcontainer/
├── codex-history.sh     # Imports and links persistent local Codex transcripts
├── devcontainer.json    # Main configuration (cross-platform)
└── README.md            # This file
```

The container is built from the root `Dockerfile` (Ubuntu 24.04) and includes all tools needed for Terraform, Kubernetes, AWS, GitOps, and MCP-based AI agent workflows.

## Security Posture

This devcontainer follows the principle of least privilege:

| Risk Area | Mitigation |
|-----------|------------|
| No `--privileged` | No features require privileged mode |
| No Docker socket mount | Docker CLI not required by any scripts or modules |
| No `--network=host` | Scoped `forwardPorts: [8080]` for ArgoCD UI |
| `--security-opt=no-new-privileges` | Prevents SUID/SGID privilege escalation inside container |
| Scoped credential mount | Only `~/.aws/eks-devcontainer` is mounted — not all of `~/.aws` |
| `~/.kube` not mounted | Created empty at runtime; `connect` stage populates it |
| Split Codex persistence | Host transcripts are read-only; host Codex config and authentication are not mounted |
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
| `REPO_ROOT` | `/workspaces/<repo>` | Repository root inside container |
| `AWS_PROFILE` | `csoc` | AWS CLI profile selector |
| `AWS_REGION` | from `config/shared.auto.tfvars.json` | Set by `container-init.sh` at runtime |
| `AWS_DEFAULT_REGION` | same as `AWS_REGION` | Set by `container-init.sh` at runtime |

`AWS_REGION` and `AWS_DEFAULT_REGION` are written to `~/.container-env` by the
`setup` stage and sourced in `.bashrc` for subsequent terminals. Terraform data
directories remain local to each generated Terragrunt unit.

## Credential Mount

The devcontainer mounts a **scoped** subdirectory — not the entire `~/.aws`:

```
Host:      ~/.aws/eks-devcontainer/   →   Container: /home/vscode/.aws/
```

This means only credentials written to `~/.aws/eks-devcontainer/` on the host are visible inside the container. Host profiles, static keys, and other credentials are never exposed.

### Windows/WSL mount source

This repository's Windows/WSL workflow uses `USERPROFILE` for scoped host
mounts. Do not concatenate `HOME` and `USERPROFILE`: both are populated in WSL,
which produces an invalid path. `mfa-session.sh` resolves this same Windows
profile directory before writing credentials.

```json
"mounts": [
  "source=${localEnv:USERPROFILE}/.aws/eks-devcontainer,target=/home/vscode/.aws,type=bind,consistency=cached"
]
```

For a native Linux or macOS host, launch VS Code with `USERPROFILE` mapped to
the local home directory before opening the devcontainer:

```bash
USERPROFILE="$HOME" code .
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

## Codex Chat History

Codex stores local transcripts under `$CODEX_HOME/sessions`. A newly created
Docker volume starts empty, so mounting only `/home/vscode/.codex` preserves
future container chats but does not import chats that already exist on the
host. Directly bind-mounting the entire host `.codex` directory is also a poor
fit here: the host and Linux container have different ownership, paths,
credential stores, platform configuration, SQLite state, and IPC sockets.

This devcontainer separates portable transcripts from machine-specific state:

| Path | Storage | Purpose |
|------|---------|---------|
| `/home/vscode/.codex` | `gen3-kro-codex` volume | Per-project config, login cache, databases, logs, plugins, and IPC |
| `/home/vscode/.codex-history` | `codex-devcontainer-history` volume | Shared transcript files for devcontainers using the same Docker daemon |
| `/mnt/codex-host-sessions` | Read-only host bind mount | Source for importing existing host transcripts |

`.devcontainer/codex-history.sh` runs at container creation and start. It
imports only `*.jsonl` transcript files, retains a backup if it migrates an
existing container session directory, and links `$CODEX_HOME/sessions` to the
shared history volume. It never imports `auth.json`, `config.toml`, SQLite
databases, caches, or IPC sockets.

Important behavior:

- Rebuild the devcontainer after changing `.devcontainer/devcontainer.json`;
  restarting the old container does not add new mounts.
- The history is local to the current Docker daemon. It is not cloud sync and
  does not follow you to another machine or a replaced Docker data store.
- Host sessions record host workspace paths while container sessions use
  `/workspaces/...`. Use `codex resume --all` when the default current-directory
  filter does not show an imported session.
- Do not resume the same session concurrently in two containers; both processes
  would append to the same transcript file.
- Other devcontainers can share these transcripts by mounting the same
  `codex-devcontainer-history` volume and linking their own
  `$CODEX_HOME/sessions` to its `sessions` directory. Keep their config,
  authentication, SQLite, cache, and IPC state in separate volumes.
- Do not remove the `codex-devcontainer-history` Docker volume unless you intend
  to remove the container-side copy of the chat transcripts.

To confirm persistence from inside the container:

```bash
echo "$CODEX_HOME"
readlink -f "$CODEX_HOME/sessions"
codex resume --all
```

## Post-Create Lifecycle

`devcontainer.json` runs setup once after creation and reconnects on each start:

```bash
bash scripts/container-init.sh setup
bash scripts/container-init.sh connect
```

### Stage Reference

Each positional flag is opt-in. With no flags, the script is a safe no-op.

| Stage | What it does |
|-------|-------------|
| `setup` | Import persistent Codex transcripts, create local directories, validate AWS credentials, write non-secret environment values, configure MCP/Codex, and mark the repository as safe |
| `connect` | Read `config/shared.auto.tfvars.json` for cluster name/region, run `aws eks update-kubeconfig`, retrieve ArgoCD admin password, start `kubectl port-forward` for ArgoCD UI on port 8080 |

### Common stage combinations

```jsonc
// devcontainer.json → postCreateCommand examples:

// Dev: environment setup only (no Terraform)
"bash scripts/container-init.sh setup"

// Reconnect to an existing cluster on container start (no Terraform)
"bash scripts/container-init.sh connect"

// Deploy infrastructure explicitly from a terminal:
// bash terragrunt/live/aws/csoc-core/stack.sh plan
// bash terragrunt/live/aws/csoc-core/stack.sh apply
```

All stages log to `outputs/YYYY-MM-DD/container-init.log`. Repeated runs
on the same UTC date overwrite that day's log.

## Config Source of Truth

All user-editable configuration lives in `config/shared.auto.tfvars.json`. This file drives:

- Terraform variables (auto-loaded by filename convention)
- Terragrunt stack evaluation
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
git clone <repo-url> ~/src/gen3-kro
cd ~/src/gen3-kro

# 2. Copy and populate config
cp config/shared.auto.tfvars.json.example config/shared.auto.tfvars.json

# 3. (If using developer identity for the first time)
#    bash terragrunt/live/aws/prereq-iam/stack.sh plan
#    bash terragrunt/live/aws/prereq-iam/stack.sh apply
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

# Inside the container — plan changes through Terragrunt
bash terragrunt/live/aws/csoc-core/stack.sh plan

# Inside the container — apply changes explicitly
bash terragrunt/live/aws/csoc-core/stack.sh apply

# Inside the container — destroy stack explicitly
bash terragrunt/live/aws/csoc-core/stack.sh destroy

# Reconnect to cluster (after container restart)
bash scripts/container-init.sh connect

# Validate Helm charts
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
```

> **Important:** Use the `stack.sh` in each `terragrunt/live/aws/<stack>/`
> directory for infrastructure operations. `container-init.sh` only prepares the
> development environment and connects to an existing cluster.

### ArgoCD UI

After the `connect` stage completes, the ArgoCD UI is available at:

```
https://localhost:8080
Username: admin
Password: (available in $ARGOCD_ADMIN_PASSWORD)
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

Run initialization through the appropriate live `stack.sh` so each generated
unit keeps independent Terraform metadata. On Windows, keep the repository on a
native WSL filesystem rather than `/mnt/c/...`.

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
