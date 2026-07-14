# AGENTS.md

## Scope

Terragrunt is the environment orchestration layer for CSOC infrastructure and
IAM.

## Rules

- Model dependency order explicitly across `prereq-iam`, `csoc-core`, and
  `fleet`.
- Pass role ARNs and cluster metadata through Terragrunt dependency outputs.
- Keep unit state keys stable and documented.
- Do not commit generated `.terragrunt-stack` content, generated Terraform
  files, tfstate, tfplan files, outputs, secrets, real account IDs, or ARNs with
  account IDs, or local credential artifacts.
- Use fixed S3 state keys for cross-stack contracts; never reference another
  stack's generated directory.

## Preferred Operator Flow

```bash
bash scripts/terragrunt-stack.sh prereq-iam plan
bash scripts/terragrunt-stack.sh csoc-core plan
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh fleet plan
```

Do not add workflow guidance that bypasses review of plans before apply.
