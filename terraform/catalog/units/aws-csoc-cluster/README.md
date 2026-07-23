# aws-csoc-cluster unit

Terragrunt wrapper for the
[`aws-csoc-cluster` module](../../modules/aws-csoc-cluster/README.md). It
generates the S3 backend and CSOC AWS provider, reads enabled operator roles
from `prereq/aws-csoc-operator-iam/terraform.tfstate`, passes VPC and EKS
settings from `config/shared.auto.tfvars.json`, and stores state at
`csoc/aws-csoc-cluster/terraform.tfstate`.

## Architecture

```text
Stage 1 - operator module                    Stage 2 - cluster unit

┌─ Unit: aws-csoc-operator-iam ─────────┐
│ ┌─ Module: aws-csoc-operator-iam ───┐ │
│ │                                   ├─┼──────────────┐
│ └───────────────────────────────────┘ │              │
└───────────────────────────────────────┘              │
                                                       ▼
                              ┌─ Unit: aws-csoc-cluster ───────────────────────────┐
                              │ ┌─ Module: aws-csoc-cluster ─────────────────────┐ │
                              │ │                                                │ │
                              │ │ ┌─ Module: terraform-aws-vpc ┐                 │ │
                              │ │ │                            ├──────────────┐  │ │
                              │ │ └────────────────────────────┘              │  │ │
                              │ │                                             ▼  │ │
                              │ │                     ┌─ Module: terraform-aws-eks ┐│ │
                              │ │                     │                           ││ │
                              │ │                     └───────────────────────────┘│ │
                              │ └────────────────────────────────────────────────┘ │
                              └────────────────────────────────────────────────────┘
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Remote-state dependency on `prereq/aws-csoc-operator-iam/terraform.tfstate`
  for explicit EKS access entries.
- Exports cluster identity and connectivity to downstream units.
- Live owner: [`csoc-cluster-core`](../../../terragrunt/live/aws/csoc-cluster-core/README.md).
