# Operators IAM stack

This stack owns the independent `aws-csoc-operator-iam` unit. It manages
MFA-gated roles and assume-role policies for existing IAM users; it does not
create users, cluster resources, spoke resources, or workstation files.

Configuration comes only from `aws_csoc_operator_iam` in the ignored
`config/shared.auto.tfvars.json`. There is no legacy configuration fallback.

## Architecture

```text
Stage 1 - stack entrypoint   Stage 2 - operator IAM
Orchestration order: earlier ───────────────→ later

┌──────────────────────┐   ┌──────────────────────────────┐
│ Stack: operators-iam ├──→┤ Unit: aws-csoc-operator-iam │
└──────────────────────┘   └──────────────────────────────┘
```

The connector represents stack orchestration.

## State and runbook

The canonical state key is
`prereq/aws-csoc-operator-iam/terraform.tfstate`.

```bash
bash scripts/terragrunt-stack.sh operators-iam plan aws-csoc-operator-iam
# Apply only after reviewing the complete plan.
bash scripts/operator-profile.sh
bash scripts/mfa-session.sh <MFA_CODE> --role-key infrastructure-admin
```

The registered MFA device is deliberately exempt from physical renaming.
