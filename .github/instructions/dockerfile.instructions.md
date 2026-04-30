---
description: 'Dockerfile and DevContainer conventions for the EKS CSOC workflow'
applyTo: "Dockerfile,.devcontainer/**"
---

# Dockerfile & DevContainer

## Scope

The DevContainer and Dockerfile serve the **EKS CSOC workflow only**.
The local CSOC workflow runs on the host — no container is used.
Do **not** add Kind or local CSOC tooling to the Dockerfile or devcontainer.json.

## Base Image

`mcr.microsoft.com/devcontainers/base:ubuntu-24.04`

## Tool Version Pinning

All tool versions are pinned as `ARG` directives:

| Tool | ARG Name | Version |
|------|----------|---------|
| Terraform | `TERRAFORM_VERSION` | 1.13.5 |
| Terragrunt | `TERRAGRUNT_VERSION` | 0.99.1 |
| kubectl | `KUBECTL_VERSION` | 1.35.1 |
| Helm | `HELM_VERSION` | 3.16.1 |
| AWS CLI | `AWS_CLI_VERSION` | 2.32.0 |
| yq | `YQ_VERSION` | 4.44.3 |
| uv | `UV_VERSION` | 0.10.2 |

When bumping a version, update only the `ARG` value and verify downstream compatibility.

## What Is and Is Not Included

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

- `~/.aws/eks-devcontainer` → `/home/vscode/.aws` (read-write) — MFA credentials

Do **not** mount `~/.kube` — EKS kubeconfig is fetched by `container-init.sh`
via `aws eks update-kubeconfig` at container start.
