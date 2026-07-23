# AGENTS.md

## Scope

This tree contains per-spoke IAM policy sources and operator-role policy
templates.

## IAM Rules

- Keep policies least-privilege and file-driven.
- Use placeholders or template variables for account-specific values.
- Require exact CSOC controller and approved operator role trust from state
  contracts.
- Do not add account-root or wildcard operator trust.

## Safety

Never commit real account IDs, ARNs with account IDs, secrets, access keys,
session tokens, tfstate, generated `.terragrunt-stack` content, outputs, or
local credential artifacts.

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
