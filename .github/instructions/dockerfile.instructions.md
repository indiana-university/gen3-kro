---
applyTo: "Dockerfile,.devcontainer/**"
---

# Dockerfile & DevContainer Instructions

These rules apply when editing the container image or DevContainer config.

## Scope

The DevContainer and Dockerfile serve the **EKS CSOC workflow only**.
The local CSOC workflow runs on the host — no container is used.
Do **not** add Kind or local CSOC tooling to the Dockerfile or devcontainer.json.

## Base Image

Ubuntu 24.04 via `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`.

## Tool Version Pinning

All tool versions are pinned as `ARG` directives for reproducibility:

| Tool | ARG Name | Version |
|------|----------|---------|
| Terraform | `TERRAFORM_VERSION` | 1.13.5 |
| Terragrunt | `TERRAGRUNT_VERSION` | 0.99.1 |
| kubectl | `KUBECTL_VERSION` | 1.35.1 |
| Helm | `HELM_VERSION` | 3.16.1 |
| AWS CLI | `AWS_CLI_VERSION` | 2.32.0 |
| yq | `YQ_VERSION` | 4.44.3 |
| uv | `UV_VERSION` | 0.10.2 |

When bumping versions, update the corresponding ARG and verify downstream
compatibility.

## What's Included vs Not Included

| Included | Not Included |
|----------|-------------|
| Terraform + Terragrunt | Kind binary |
| AWS CLI v2 | Docker CLI |
| kubectl, Helm, yq | Local CSOC scripts |
| uv/uvx for Python tools | devcontainer-local.json |

## Security Posture

- `--security-opt=no-new-privileges` in devcontainer.json
- User: `vscode` (non-root)
- `overrideCommand: false` — container runs its own entrypoint

## Mount Conventions

The DevContainer mounts:
- `~/.aws/eks-devcontainer` → `/home/vscode/.aws` (read-write) — MFA-assumed-role credentials

Do **not** mount `~/.kube` — EKS kubeconfig is fetched by `container-init.sh`
via `aws eks update-kubeconfig` at container start.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AWS_PROFILE` | `csoc` — MFA-assumed-role profile |
| `KUBE_EDITOR` | `code --wait` |

## DevContainer Entrypoint

`container-init.sh` runs automatically when the container starts. It:
1. Validates AWS credentials
2. Fetches CSOC kubeconfig via `aws eks update-kubeconfig`
3. Sets up any required port-forwards

When modifying `container-init.sh`, keep it idempotent — it runs on every
container start.

## Copilot Instruction Files

`devcontainer.json` includes:
```json
"chat.instructionsFilesLocations": {
  ".github/instructions": true
}
```

This allows per-glob instruction files in `.github/instructions/` to load
automatically when editing matching files in VS Code.
