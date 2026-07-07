# AGENTS.md

## Scope

The devcontainer is a reproducible toolchain for CSOC operations. It is not the
deployment orchestrator.

## Rules

- Keep Terraform, Terragrunt, AWS CLI, kubectl, Helm, yq, uv, and Node tooling
  versioned in the Dockerfile.
- Mount only `~/.aws/eks-devcontainer` into `/home/vscode/.aws`.
- Do not mount host `~/.kube`.
- Do not set lifecycle commands that auto-apply infrastructure by default.
- Prefer `setup` or `setup connect` for container lifecycle commands.

## Safety

Do not add secrets, real account IDs, ARNs with account IDs, tfstate,
`.terragrunt-stack` content, generated outputs, or local credential artifacts
to tracked files.
