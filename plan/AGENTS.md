# AGENTS.md

## Scope

This folder is the architectural source of truth for the CSOC provisioning
separation work.

## Rules

- Keep plan documents decision-oriented and implementable.
- Preserve migration ordering: baseline, module split, Terragrunt stack, state
  migration, IAM/operator hardening, documentation cleanup.
- Do not rewrite the plan to skip the compatibility wrapper or state migration.
- When repo reality changes, update the assessment, target model, and roadmap
  together so they do not contradict each other.
- Do not include real account IDs, ARNs with account IDs, secrets, tfstate,
  generated `.terragrunt-stack` content, `outputs/`, or local credential
  artifacts.
