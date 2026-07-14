# AGENTS.md

## Scope

This tree contains IAM policy source files and developer identity policy
templates.

## IAM Rules

- Keep policies least-privilege and file-driven.
- Use placeholders or template variables for account-specific values.
- Require exact CSOC role trust from the controller IAM state contract.
- Do not broaden devcontainer trust without documenting the manual cleanup use
  case.

## Safety

Never commit real account IDs, ARNs with account IDs, secrets, access keys,
session tokens, tfstate, generated `.terragrunt-stack` content, outputs, or
local credential artifacts.
