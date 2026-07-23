# aws-csoc-operator-iam unit

This Terragrunt unit wraps the identically named
[`aws-csoc-operator-iam` module](../../modules/aws-csoc-operator-iam/README.md).
It supplies the CSOC AWS provider, reads the operator role/user configuration,
and stores state at
`prereq/aws-csoc-operator-iam/terraform.tfstate`.

## Architecture

```text
Stage 1 - independent unit

┌─ Unit: aws-csoc-operator-iam ──────────────┐
│                                           │
│ ┌─ Module: aws-csoc-operator-iam ───────┐ │
│ │                                      │ │
│ └──────────────────────────────────────┘ │
│                                           │
└───────────────────────────────────────────┘
```

Nesting means composition. This unit has no Terraform unit dependencies and
does not use Kubernetes, Helm, or local providers.
