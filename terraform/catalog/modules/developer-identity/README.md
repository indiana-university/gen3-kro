# Developer Identity — MFA + Scoped Role for Devcontainer

One-time bootstrap module that creates:

1. A **virtual MFA device** for the IAM user
2. A **scoped IAM role** (`{csoc_alias}-csoc-user`) with least-privilege permissions
3. An **assume-role policy** on the IAM user

After setup, the devcontainer uses **short-lived, MFA-gated, scoped credentials** instead of
static IAM access keys.

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│                        HOST                             │          CONTAINER
│                                                         │
│  ┌──────────────────────────────────┐                   │  ┌──────────────────────────┐
│  │ ~/.aws/credentials               │                   │  │ ~/.aws (bind mount)      │
│  │  [csoc]  ← static keys           │                   │  │                          │
│  │  [eks-devcontainer] ← temp creds │───── bind-mount ──│──│ AWS_PROFILE=             │
│  │                                  │                   │  │   eks-devcontainer       │
│  └──────────────────────────────────┘                   │  │                          │
│           │                                             │  │ Scoped permissions:      │
│           │  scripts/mfa-session.sh <CODE>              │  │  EKS, VPC, IAM, S3,      │
│           │  ├─ aws sts assume-role (with MFA)          │  │  KMS, SecretsManager,    │
│           │  └─ writes temp creds → [eks-devcontainer]  │  │  RDS, ElastiCache,       │
│           │                                             │  │  OpenSearch, Logs        │
│           ▼                                             │  │                          │
│  ┌──────────────────────────────────┐                   │  │ Expires after 12h        │
│  │ IAM Role:                        │                   │  └──────────────────────────┘
│  │  {csoc_alias}-csoc-user          │                   │
│  │                                  │                   │
│  │  Trust: Terraform.User + MFA     │                   │
│  │  Perms: project-scoped only      │                   │
│  └──────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- AWS CLI installed on the host
- An authenticator app (Google Authenticator, Authy, 1Password, etc.)
- The `csoc` profile configured in `~/.aws/credentials` with static keys

## Setup (One-Time)

### Step 1: Apply the Terraform module

```bash
cd terraform/catalog/modules/developer-identity

# Optional: copy and edit the tfvars
cp secrets.tfvars.example secrets.tfvars

terraform init
terraform apply
```

This creates the MFA device and IAM role. The output includes:

- MFA registration instructions (Base32 seed + otpauth URI)
- AWS CLI profile configuration snippet
- The `enable-mfa-device` command to run

### Step 2: Register MFA in your authenticator app

Use the **Base32 seed** or **QR code URI** from the Terraform output to add the account to your
authenticator app.

```bash
# View the sensitive outputs
terraform output -raw mfa_base32_seed
terraform output -raw mfa_qr_code_uri
```

### Step 3: Enable the MFA device

Get **two consecutive codes** from your authenticator app and run:

```bash
aws iam enable-mfa-device \
  --user-name Terraform.User \
  --serial-number <MFA_ARN_FROM_OUTPUT> \
  --authentication-code-1 <CODE_1> \
  --authentication-code-2 <CODE_2> \
  --profile csoc
```

### Step 4: Add the profile to ~/.aws/config

```ini
[profile eks-devcontainer]
role_arn = arn:aws:iam::<CSOC_ACCOUNT_ID>:role/<CSOC_ALIAS>-csoc-user
source_profile = <your-base-aws-profile>
mfa_serial = arn:aws:iam::<CSOC_ACCOUNT_ID>:mfa/<YOUR_IAM_USERNAME>-virtual-mfa
region = us-east-1
output = yaml
duration_seconds = 43200
```

Or copy the snippet from `outputs/aws-config-snippet.ini`.

### Step 5: Test

```bash
# This prompts for your MFA code:
aws sts get-caller-identity --profile eks-devcontainer
```

## Daily Usage

### Before starting the devcontainer

```bash
# From the repo root on the HOST:
bash scripts/mfa-session.sh <MFA_CODE>

# This writes temp creds to ~/.aws/credentials [eks-devcontainer]
# Valid for 12 hours (configurable)
```

### Start the devcontainer

The devcontainer.json is pre-configured with `AWS_PROFILE=eks-devcontainer`.
All tools inside the container (Terraform, AWS CLI, kubectl) automatically use the
scoped, time-limited credentials.

### When credentials expire

Re-run `mfa-session.sh` on the host with a new MFA code. The container picks up
the refreshed credentials immediately via the bind mount.

## Script Reference

### scripts/mfa-session.sh

```text
Usage: bash scripts/mfa-session.sh <MFA_CODE> [OPTIONS]

Options:
  --duration SECONDS       Session duration (default: 43200 = 12h)
  --profile PROFILE        Source AWS profile (default: csoc)
  --role-arn ARN           Role to assume (auto-detected from config)
  --mfa-serial ARN         MFA device ARN (auto-detected from IAM)
  --session-profile NAME   Target credentials profile (default: eks-devcontainer)

Environment Variables:
  MFA_SOURCE_PROFILE       Override source profile
  MFA_ROLE_ARN             Override role ARN
  MFA_SERIAL_ARN           Override MFA serial
  MFA_SESSION_PROFILE      Override session profile name
  MFA_DURATION             Override session duration
```

## Security Improvements vs Previous Setup

| Before | After |
| ------ | ----- |
| Static long-lived IAM access keys | Temporary credentials (12h max) |
| Full PowerUser + IAMFullAccess | Scoped to project needs only |
| No MFA required | MFA required to obtain credentials |
| Credentials usable indefinitely if leaked | Credentials expire automatically |
| Same permissions everywhere | Container gets only what it needs |

## Files Created

| Path | Purpose |
| ---- | ------- |
| `terraform/catalog/modules/developer-identity/` | Terraform module (IaC) |
| `scripts/mfa-session.sh` | Host-side MFA session helper |
| `outputs/mfa-setup-instructions.txt` | Generated after `terraform apply` |
| `outputs/aws-config-snippet.ini` | Generated AWS profile config |

## Cleanup

```bash
cd terraform/catalog/modules/developer-identity
terraform destroy
```

This removes the MFA device, IAM role, and policies. You'll need to remove the
`[eks-devcontainer]` profile from `~/.aws/config` and `~/.aws/credentials` manually.
