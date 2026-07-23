# aws-spoke-access-iam unit

Terragrunt wrapper for the
[`aws-spoke-access-iam` module](../../modules/aws-spoke-access-iam/README.md). It generates an
S3 backend that remains in the CSOC state account, configures the AWS provider
for the selected spoke account, reads controller and operator IAM remote state
from `csoc/aws-csoc-controller-iam/terraform.tfstate` and
`prereq/aws-csoc-operator-iam/terraform.tfstate`, and stores per-spoke state at
`spokes/<alias>/aws-spoke-access-iam/terraform.tfstate`.

## Architecture

```text
Stage 1 - prerequisite modules                        Stage 2 - target module

┌─ Unit: aws-csoc-controller-iam ──────────┐        ┌─ Unit: aws-spoke-access-iam (selected spoke) ┐
│ ┌─ Module: aws-csoc-controller-iam ┐ │        │ ┌─ Module: aws-spoke-access-iam ────────────┐ │
│ │                                  ├─┼─────┬──┼→┤                                          │ │
│ └──────────────────────────────────┘ │     │  │ └──────────────────────────────────────────┘ │
└──────────────────────────────────────┘     │  └──────────────────────────────────────────────┘
                                             │
┌─ Unit: aws-csoc-operator-iam ───────────┐  │
│ ┌─ Module: aws-csoc-operator-iam ─────┐ │  │
│ │                                    ├─┼──┘
│ └────────────────────────────────────┘ │
└────────────────────────────────────────┘
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Remote-state dependency on `csoc/aws-csoc-controller-iam/terraform.tfstate`.
- Remote-state dependency on
  `prereq/aws-csoc-operator-iam/terraform.tfstate`.
- No Terragrunt `dependency` block; the wrapper generates a Terraform remote-state data source.
- Live owner: [`spoke-fleet-update`](../../../terragrunt/live/aws/spoke-fleet-update/README.md).
