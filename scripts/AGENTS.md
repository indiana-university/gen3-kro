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

## Architecture Diagram Semantics

- Nesting means ownership or containment; it never means dependency.
- A solid connector between resource boxes means the destination consumes data,
  configuration, or a reference from the source. Draw fan-out and fan-in with
  explicit tee branches, keep arrowheads touching consumers, and leave resources
  unconnected when no such flow exists.
- Do not turn `depends_on`, Terragrunt ordering, Argo CD sync waves, an opaque
  ordering token, or observed apply sequence into a resource-data connector.
  Show ordering-only information with one detached guide such as `Deployment
  order only (not resource data): earlier -> later`, and arrange the diagram in
  that general direction.
- State connector meanings in a legend or adjacent text. Unit, module, or stack
  orchestration connectors may represent ordering when labeled; a connector
  must not silently switch between containment, data flow, and ordering.
