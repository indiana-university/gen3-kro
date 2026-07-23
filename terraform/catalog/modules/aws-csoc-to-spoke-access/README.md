# AWS CSOC spoke access

This AWS-only module attaches one inline policy to the existing CSOC ACK source
role. The policy permits `sts:AssumeRole` and `sts:TagSession` on the sorted,
deduplicated set of exact spoke access-role ARNs.

No policy is created when `source_role_name` is empty or the compacted ARN set is
empty. The module does not create the source role or spoke roles and does not
construct wildcard ARNs.

## Architecture

```text
Prerequisites/Dependencies                                     IAM resources for CSOC role to assume spoke roles.
┌─────────────────────────────────────────┐                    ┌──────────────────────────────────┐
│ Module: aws-csoc-controller-iam         │                    │ Module: aws-csoc-to-spoke-access    │
│ ┌─────────────────────────────────┐     │                    │                                  │
│ │ CSOC ACK source IAM role        ├─────┼──────────────→┐    │ ┌──────────────────────────────┐ │
│ └─────────────────────────────────┘     │               ├────┼→┤ CSOC ACK assume-spoke policy │ │
└─────────────────────────────────────────┘               │    │ └──────────────────────────────┘ │
                                                          │    └──────────────────────────────────┘
                                                          │
                                                          │
                                                          │
┌─────────────────────────────────────────┐               │
│ Module: aws-spoke-access-iam (1)               │               │
│ ┌─────────────────────────────────┐     │               │
│ │ Spoke 1 ACK IAM role            ├─────┼──────────────→┤
│ └─────────────────────────────────┘     │               │
└─────────────────────────────────────────┘               │
┌─────────────────────────────────────────┐               │
│ Module: aws-spoke-access-iam (2)               │               │
│ ┌─────────────────────────────────┐     │               │
│ │ Spoke 2 ACK IAM role            ├─────┼──────────────→┤
│ └─────────────────────────────────┘     │               │
└─────────────────────────────────────────┘               │
┌─────────────────────────────────────────┐               │
│ Module: aws-spoke-access-iam (N)               │               │
│ ┌─────────────────────────────────┐     │               │
│ │ ... ACK IAM role                ├─────┼──────────────→┘
│ └─────────────────────────────────┘     │
└─────────────────────────────────────────┘
```

This module depends on controller IAM having already created the CSOC source
role and on one or more `aws-spoke-access-iam` instances having already exported exact
spoke role ARNs.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `source_role_name` | required | Existing CSOC role receiving the inline policy. |
| `spoke_role_arns` | `{}` | Map of spoke aliases to exact role ARNs; empty values are ignored. |
| `policy_name` | `ack-assume-spoke-roles` | Inline IAM policy name. |

| Output | Meaning |
| --- | --- |
| `spoke_role_arns` | Effective sorted, unique, non-empty ARN list. |
| `policy_name` | Created inline policy name, or `null` when disabled. |

The live owner is `aws-csoc-to-spoke-access` in the
[`spoke-fleet-update` stack](../../../../terragrunt/live/aws/spoke-fleet-update/README.md), with state
key `csoc/aws-csoc-to-spoke-access/terraform.tfstate`.
