# CSOC operator IAM

This AWS-only module manages MFA-gated operator roles for existing IAM users.
It never creates or deletes IAM users. Role-to-user assignments are explicit:
each role trusts only its assigned user ARNs and explicit principal ARNs, while
each configured user receives one policy containing only the role ARNs assigned
to that user.

Use the [`operators-iam` stack](../../../../terragrunt/live/aws/operators-iam/README.md).
That stack renders the file-driven policies under `iam/operator-roles/`, owns
the backend, and derives function-aware role names.

## Architecture

```text
Stage 1 - existing identities       Stage 2 - operator roles             Stage 3 - attached permissions

┌────────────────────────────┐     ┌─ Module: aws-csoc-operator-iam ──────────────────────────────────────────────┐
│ Existing operator IAM user ├────→│ ┌────────────────────────────┐     ┌───────────────────────────────┐         │
└────────────────────────────┘     │ │ Infrastructure-admin role  ├────→│ Infrastructure-admin policy   │         │
                                   │ └────────────────────────────┘     └───────────────────────────────┘         │
                                   │                                                                            │
                                   │ ┌────────────────────────────┐     ┌───────────────────────────────┐         │
                                   │ │ Platform-operator role     ├────→│ Platform-operator policy      │         │
                                   │ └────────────────────────────┘     └───────────────────────────────┘         │
                                   │                                                                            │
                                   │ ┌────────────────────────────┐     ┌───────────────────────────────┐         │
                                   │ │ Virtual MFA devices        │     │ User assume-role policies     │         │
                                   │ │ ┌────────────────────────┐ │     │ ┌───────────────────────────┐ │         │
                                   │ │ │ Primary operator MFA   │ │     │ │ Primary user assignments  │ │         │
                                   │ │ ├────────────────────────┤ │     │ ├───────────────────────────┤ │         │
                                   │ │ │ Additional user MFA    │ │     │ │ Additional assignments    │ │         │
                                   │ │ ├────────────────────────┤ │     │ ├───────────────────────────┤ │         │
                                   │ │ │ ...                    │ │     │ │ ...                       │ │         │
                                   │ │ └────────────────────────┘ │     │ └───────────────────────────┘ │         │
                                   │ └────────────────────────────┘     └───────────────────────────────┘         │
                                   └────────────────────────────────────────────────────────────────────────────┘
```

Solid arrows mean the destination consumes the source identity or role
reference. Nested boxes mean containment.

## Contract

| Input | Meaning |
| --- | --- |
| `users` | Existing users keyed by stable aliases, with optional Terraform-managed MFA and assume-policy settings. |
| `roles` | Enabled role definitions, assignments, exact principals, MFA/session settings, permission JSON, EKS access policy, and spoke-access flag. |
| `default_role_key` | Default selected by session tooling; `infrastructure-admin` by default. |
| `tags` | Common IAM role and virtual-MFA tags. |

| Output | Meaning |
| --- | --- |
| `role_arns`, `role_names` | Enabled operator roles keyed by function. |
| `user_role_arns` | Exact role assignments keyed by user alias. |
| `mfa_device_arns` | Managed MFA device ARNs keyed by user alias. |
| `mfa_enrollment` | Sensitive enrollment material for newly created virtual MFA devices. |
| `spoke_access_role_arns` | Exact roles approved for optional manual spoke access. |
| `eks_access_entries` | Operator principals and EKS access-policy ARNs consumed by `aws-csoc-cluster`. |

Enabled roles must have at least one assigned user or explicit principal.
Unknown user keys, duplicate role/MFA names, malformed policies, and invalid
session durations fail validation. Human roles require MFA by default.

The module contains no legacy configuration projection or compatibility
resources. The registered MFA device retains its existing physical name and
tags; operator role names and tags use the canonical stack and module
ownership.

The module no longer writes workstation files. Run
`bash scripts/operator-profile.sh`, followed by
`bash scripts/mfa-session.sh <MFA_CODE> --role-key infrastructure-admin`.
