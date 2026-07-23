# aws-csoc-controller-iam unit

Terragrunt wrapper for the
[`aws-csoc-controller-iam` module](../../modules/aws-csoc-controller-iam/README.md).
It generates the S3 backend and CSOC AWS provider, reads cluster outputs from
`../aws-csoc-cluster`, and stores state at
`csoc/aws-csoc-controller-iam/terraform.tfstate`.

## Architecture

```text
Stage 1 - prerequisite modules           Stage 2 - target module

┌─ Unit: aws-csoc-cluster ──────────┐        ┌─ Unit: aws-csoc-controller-iam ─────────────────────┐
│                               │        │                                                 │
│ ┌─ Module: aws-csoc-cluster ┐ │        │ ┌─ Module: aws-csoc-controller-iam ───────────┐ │
│ │                           ├─┼────────┼→┤                                             │ │
│ └───────────────────────────┘ │        │ │                                             │ │
│                               │        │ │ ┌─ Module: terraform-aws-eks-pod-identity ┐ │ │
└───────────────────────────────┘        │ │ │                                         │ │ │
                                         │ │ └─────────────────────────────────────────┘ │ │
                                         │ └─────────────────────────────────────────────┘ │
                                         │                                                 │
                                         └─────────────────────────────────────────────────┘
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Direct Terragrunt dependency: `aws-csoc-cluster`.
- Reads no remote state directly; dependency outputs are injected by Terragrunt.
- Live owner: [`csoc-cluster-core`](../../../terragrunt/live/aws/csoc-cluster-core/README.md).
