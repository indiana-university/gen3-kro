# config/ — Environment-Specific Input Files

All manually-edited configuration files live here. This directory is
**gitignored** (real files only) — example templates are tracked.

## Setup

Copy each `.example` file, remove the `.example` suffix, and fill in your values:

```bash
cp config/shared.auto.tfvars.json.example  config/shared.auto.tfvars.json
cp config/ssm-repo-secrets/input.json.example  config/ssm-repo-secrets/input.json
# Place your GitHub App private key (.pem) in config/ssm-repo-secrets/
```

## Files

| File | Purpose | Consumed By |
|------|---------|-------------|
| `shared.auto.tfvars.json` | **Single source of truth** — all Terraform + Terragrunt + backend config | `install.sh`, `destroy.sh`, Terragrunt stack |
| `ssm-repo-secrets/input.json` | GitHub App credentials for ArgoCD repo access | `scripts/ssm-repo-secrets/generate-ssm-payload.sh` |
| `ssm-repo-secrets/*.pem` | GitHub App private key(s) | Referenced by `input.json` |

### Unused Files (not required)

| File | Notes |
|------|-------|
| `terraform.tfvars` | Terraform variables are in `shared.auto.tfvars.json` |
| `backend.hcl` | Backend config (`backend_bucket`, `backend_key`, `backend_region`) is in `shared.auto.tfvars.json` |
| `secrets.yaml` | Terragrunt reads `spokes`, `developer_identity` from `shared.auto.tfvars.json` |

## Security

- **Never commit** real config files — they contain account IDs, credentials, and secret paths.
- The `.gitignore` ignores everything in `config/` except `*.example` and `README.md`.
- Keep private keys (`.pem`) in `config/ssm-repo-secrets/` only.
