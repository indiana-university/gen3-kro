# aws-spoke-access-iam

AWS-only module that runs in one spoke account. It creates one access role for
each enabled role-map entry. Physical names include the role key:
`<spoke_alias>-<role_key>-access-role`.

The trust document always names the exact CSOC controller ARN. Optional manual
access is an exact set of operator role ARNs received from
`aws-csoc-operator-iam`; there is no account-root or wildcard trust path.

AWS-managed policies attach directly. Custom statements are split into chunks
of eight. Chunk zero is an inline policy and later chunks are managed policies;
all policy names include the spoke alias, role key, and chunk index.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `cluster_name` | required | Existing CSOC EKS cluster used in descriptions and tags. |
| `csoc_source_role_arn` | required | Exact controller role trusted by every enabled role. |
| `manual_operator_role_arns` | `[]` | Exact operator roles approved for manual spoke access. |
| `roles` | `{}` | Role-key map with enablement and policy configuration. |
| `spoke_alias` | required | Spoke identifier used in physical names. |
| `tags` | `{}` | Additional IAM tags. |

`role_arns` and `role_names` retain maps keyed by role function. The unit also
exports `ack_controller_access_role_arn` for the normal `ack-controller` entry.

## Architecture

```text
Stage 1 - trusted identities                    Stage 2 - spoke access

┌─ Module: aws-csoc-controller-iam ───────┐
│ ┌─────────────────────────────────────┐ │
│ │ ACK controller IAM role             ├─┼─────────────┐
│ └─────────────────────────────────────┘ │             │
└─────────────────────────────────────────┘             │
                                                        │
┌─ Module: aws-csoc-operator-iam ─────────┐             │
│ ┌─────────────────────────────────────┐ │             │
│ │ Approved operator IAM roles         ├─┼─────────────┤
│ └─────────────────────────────────────┘ │             │
└─────────────────────────────────────────┘             │
                                                        │
                                                        ▼
                                          ┌─ Module: aws-spoke-access-iam ─────────────┐
                                          │                                            │
                                          │ ┌────────────────────────────────────────┐ │
                                          │ │ Spoke access IAM roles                 │ │
                                          │ │ ┌────────────────────────────────────┐ │ │
                                          │ │ │ ack-controller access role         │ │ │
                                          │ │ └────────────────────────────────────┘ │ │
                                          │ │ ┌────────────────────────────────────┐ │ │
                                          │ │ │ another-role access role           │ │ │
                                          │ │ └────────────────────────────────────┘ │ │
                                          │ │ ┌─────┐                                │ │
                                          │ │ │ ... │                                │ │
                                          │ │ └─────┘                                │ │
                                          │ └──────────────────┬─────────────────────┘ │
                                          │                    ├───────────────┐       │
                                          │                    ▼               ▼       │
                                          │ ┌──────────────────────┐ ┌────────────────┐│
                                          │ │ Inline policy chunks │ │ Managed policy ││
                                          │ └──────────────────────┘ └────────────────┘│
                                          └────────────────────────────────────────────┘
```

Nested boxes show ownership. Connectors show trust inputs or role-to-policy
references. The live owner is `aws-spoke-access-iam-<alias>` in the
[`spoke-fleet-update` stack](../../../../terragrunt/live/aws/spoke-fleet-update/README.md), using
`spokes/<alias>/aws-spoke-access-iam/terraform.tfstate`.
