# terragrunt-stack.sh

Thin wrapper around Terragrunt for the three infrastructure stacks. Handles
log directory creation, `TF_DATA_DIR` cleanup, and spoke alias injection. All
output is written under `outputs/YYYY-MM-DD/terragrunt/<stack>/`.

## Usage

```bash
bash scripts/terragrunt-stack.sh <stack> <command> [unit]

# Fleet stack requires spoke alias
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update <command> [unit]
```

## Stacks

| Stack | Units | Purpose |
|-------|-------|---------|
| `operators-iam` | `aws-csoc-operator-iam` | Existing-user MFA and function-specific operator roles |
| `csoc-cluster-core` | `aws-csoc-cluster`, `aws-csoc-controller-iam`, `gitops-argocd-install` | CSOC VPC/EKS, controller IAM, Argo CD install |
| `spoke-fleet-update` | `aws-spoke-access-iam`, `aws-csoc-to-spoke-access`, `gitops-argocd-bootstrap` | Per-spoke IAM, cross-account access, fleet registration |

## Commands

| Command | Description |
|---------|-------------|
| `generate` | Generate Terragrunt unit files without running Terraform |
| `init` | Terraform init for the stack or a single unit |
| `plan` | Plan — always review before apply |
| `apply` | Apply — requires prior plan review |
| `destroy` | Destroy managed resources |
| `output` | Show Terraform outputs |

## Unit-Level Targeting

Pass a unit name as the third argument to operate on a single unit instead of
the full stack:

```bash
bash scripts/terragrunt-stack.sh csoc-cluster-core plan aws-csoc-cluster
bash scripts/terragrunt-stack.sh csoc-cluster-core apply aws-csoc-cluster

TG_SPOKE_ALIAS=spoke1 bash scripts/terragrunt-stack.sh spoke-fleet-update plan aws-spoke-access-iam
TG_SPOKE_ALIAS=spoke1 bash scripts/terragrunt-stack.sh spoke-fleet-update apply aws-spoke-access-iam
```

## State Keys

Each unit stores state independently in the configured S3 backend:

| Unit | State key |
|------|-----------|
| aws-csoc-operator-iam | `prereq/aws-csoc-operator-iam/terraform.tfstate` |
| aws-csoc-cluster | `csoc/aws-csoc-cluster/terraform.tfstate` |
| aws-csoc-controller-iam | `csoc/aws-csoc-controller-iam/terraform.tfstate` |
| aws-spoke-access-iam | `spokes/<alias>/aws-spoke-access-iam/terraform.tfstate` |
| aws-csoc-to-spoke-access | `csoc/aws-csoc-to-spoke-access/terraform.tfstate` |
| gitops-argocd-install | `csoc/gitops-argocd-install/terraform.tfstate` |
| gitops-argocd-bootstrap | `csoc/gitops-argocd-bootstrap/terraform.tfstate` |

Empty state for a unit means Terraform will propose creates. Do not apply until
that is expected for the target environment.

## Output Logs

```
outputs/YYYY-MM-DD/terragrunt/<stack>/
  <action>-core.log          # Terragrunt orchestration output
  <action>-<unit>.log        # Per-unit Terraform output
  <action>-report.json       # Native Terragrunt report (full-stack only)
  plan-files/                # Retained plan files (plan action only)
```

Repeated actions on the same UTC date overwrite that action's files only.
