# AGENTS.md

## Scope

Terragrunt is the environment orchestration layer for CSOC infrastructure and
IAM.

## Rules

- Model dependency order explicitly: developer identity, CSOC foundation, spoke
  IAM, then in-cluster bootstrap.
- Pass role ARNs and cluster metadata through Terragrunt dependency outputs.
- Keep unit state keys stable and documented.
- Do not commit generated `.terragrunt-stack` content, generated Terraform
  files, tfstate, tfplan files, outputs, secrets, real account IDs, or ARNs with
  account IDs, or local credential artifacts.
- During migration, keep the existing IAM setup stack usable until state has
  been moved safely.

## Preferred Operator Flow

```bash
cd terragrunt/live/aws/csoc
terragrunt stack run plan
terragrunt stack run apply
```

Do not add workflow guidance that bypasses review of plans before apply.
