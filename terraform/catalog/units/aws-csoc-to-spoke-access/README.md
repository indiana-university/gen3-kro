# aws-csoc-to-spoke-access unit

Terragrunt wrapper for the
[`aws-csoc-to-spoke-access` module](../../modules/aws-csoc-to-spoke-access/README.md).
It generates the S3 backend and CSOC AWS provider, reads controller IAM remote
state from `csoc/aws-csoc-controller-iam/terraform.tfstate`, depends on the selected
`../aws-spoke-access-iam-<alias>` unit for the fresh spoke role ARN, and stores state at
`csoc/aws-csoc-to-spoke-access/terraform.tfstate`.

## Architecture

```text
Stage 1 - prerequisite modules                  Stage 2 - target module

┌─ Unit: aws-csoc-controller-iam ──────────┐        ┌─ Unit: aws-csoc-to-spoke-access ──────────┐
│                                      │        │                                    │
│ ┌─ Module: aws-csoc-controller-iam ┐ │        │ ┌─ Module: aws-csoc-to-spoke-access ┐ │
│ │                                  ├─┼────────┼→┤                                │ │
│ └──────────────────────────────────┘ │        │ │                                │ │
│                                      │        │ │                                │ │
└──────────────────────────────────────┘        │ │                                │ │
                                                │ │                                │ │
                                                │ │                                │ │
┌─ Unit: aws-spoke-access-iam (selected spoke) ───┐        │ │                                │ │
│                                      │        │ │                                │ │
│ ┌─ Module: aws-spoke-access-iam ──────────┐ │        │ │                                │ │
│ │                                  ├─┼────────┼→┤                                │ │
│ └──────────────────────────────────┘ │        │ └────────────────────────────────┘ │
│                                      │        │                                    │
└──────────────────────────────────────┘        └────────────────────────────────────┘
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Direct Terragrunt dependency: selected `aws-spoke-access-iam-<alias>` unit.
- Remote-state dependency on `csoc/aws-csoc-controller-iam/terraform.tfstate`.
- Live owner: [`spoke-fleet-update`](../../../terragrunt/live/aws/spoke-fleet-update/README.md).
