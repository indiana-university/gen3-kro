# AGENTS.md

## Scope

Scripts provide operator ergonomics and reporting. They must not hide
infrastructure mutation behind surprising defaults.

## Shell Rules

- Use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Quote variables and use portable path resolution.
- Prefer shared helpers for credential tier checks and config parsing when
  touching both EKS and Kind workflows.
- Keep apply/destroy actions explicit. Do not make devcontainer or setup scripts
  auto-apply infrastructure by default.
- Use `scripts/kind-csoc.sh` for local CSOC references.

## Safety

Do not write real secrets, account IDs, ARNs with account IDs, credentials,
tfstate, generated `.terragrunt-stack` content, outputs, or local credential
artifacts into tracked source.
