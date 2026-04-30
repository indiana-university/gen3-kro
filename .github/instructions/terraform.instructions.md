---
description: 'Terraform and Terragrunt conventions for the gen3-kro EKS CSOC cluster and spoke IAM management'
applyTo: "terraform/**,terragrunt/**"
---

# Terraform & Terragrunt Conventions

## Scope

| Directory | Tool | Purpose |
|-----------|------|---------|
| `terraform/` | Terraform 1.13.5 | CSOC EKS cluster, VPC, ArgoCD bootstrap |
| `terragrunt/` | Terragrunt 0.99.1 | Spoke IAM role management (host-side) |

## Terraform Conventions

### File Organization
```
terraform/env/aws/csoc-cluster/
├── main.tf          # resources
├── variables.tf     # input variables
├── outputs.tf       # output values
└── versions.tf      # provider versions
```

### Security Rules
- Never hardcode credentials, account IDs, or ARNs
- Use `config/shared.auto.tfvars.json` (gitignored) for sensitive values
- IAM policies: specific actions and resources — no wildcards
- Enable encryption at rest for all S3 and RDS resources
- `block_public_acls = true` on all S3 buckets

### State Management
- Backend: S3 with DynamoDB locking
- Never run `terraform apply` without reviewing `terraform plan` first
- Do not commit `.tfstate`, `.tfstate.*`, or `tfplan` files (covered by .gitignore)

### Terragrunt
- Lives in `terragrunt/live/`
- Manages spoke IAM roles only (cross-account trust relationships)
- Uses `terragrunt.hcl` pattern — commit `terragrunt.hcl`, not generated `.tf` files

## Never Commit

- AWS Account IDs (12-digit numbers)
- AWS Access Key IDs (`AKIA...`)
- ARNs containing account IDs
- `*.tfstate`, `*.tfplan`, `*.auto.tfvars.json`

## Destroy Safety

Before `terraform destroy` or `terragrunt destroy`:
1. Confirm with the user — this deletes real AWS resources
2. Verify the correct workspace/environment is targeted
3. Check for resources that might require manual cleanup (Route53, ACM certs)
