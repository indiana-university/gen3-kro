# AGENTS.md

## Scope

This folder is the architectural source of truth for the CSOC provisioning
separation work.

## Rules

- Keep plan documents decision-oriented and implementable.
- Preserve the recorded migration ordering and actual live status: backend
  migration, parallel IAM cutover, authorized retired-resource cleanup, then
  first deployment.
- Do not reintroduce migration-only compatibility resources after an
  environment has crossed the recorded state-address moves.
- When repo reality changes, update the assessment, target model, and roadmap
  together so they do not contradict each other.
- Do not include real account IDs, ARNs with account IDs, secrets, tfstate,
  generated `.terragrunt-stack` content, `outputs/`, or local credential
  artifacts.
