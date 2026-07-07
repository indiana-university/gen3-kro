# AGENTS.md

## Scope

Tracked files in this directory must be examples, schema documentation, or
agent guidance only. Real environment config stays gitignored.

## Rules

- Do not commit real `shared.auto.tfvars.json`, repo secret inputs, private keys,
  secrets, account IDs, ARNs with account IDs, credentials, tfstate, generated
  `.terragrunt-stack` content, outputs, or local credential artifacts.
- Keep examples placeholder-only.
- If adding a schema or generated-input workflow, keep human-edited source config
  separate from layer-specific rendered inputs.
- `config/AGENTS.md`, `config/README.md`, and `*.example` files are the only
  intended tracked files here.
