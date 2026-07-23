# Terraform implementation layer

This tree contains reusable Terraform modules and the Terragrunt unit templates
that call them. It is not the environment entrypoint. Operators run the live
stacks under [`../terragrunt/live/aws`](../terragrunt/live/aws/README.md), which
select providers, configure remote state, and pass environment-specific values.

## Layout

| Path | Responsibility |
| --- | --- |
| [`catalog/modules`](catalog/modules/README.md) | Reusable AWS-only and in-cluster Terraform modules. |
| [`catalog/units`](catalog/units/README.md) | Reusable Terragrunt unit templates that wrap modules with providers, state, and dependencies. |

The ownership boundary is deliberate:

- AWS modules create AWS resources only and do not configure Kubernetes or Helm.
- In-cluster modules target an existing EKS cluster through providers supplied by
  a Terragrunt unit.
- Terraform installs or seeds Argo CD, but Argo CD, KRO, and ACK own continuous
  post-bootstrap reconciliation.
- Each generated Terragrunt unit has a separate, stable state key.

See [`../plan`](../plan/README.md) for the architecture decisions and migration
status. Do not add a combined Terraform root that collapses the split state.

## Development

Run read-only formatting checks from the repository root:

```bash
terraform fmt -check -recursive terraform/
terragrunt hcl format --check
git diff --check
```

Do not run `apply` or `destroy` without selecting and reviewing the intended
live environment. Never commit generated `.terraform`, `.terragrunt-stack`,
state, plan, `outputs/`, or credential files.
