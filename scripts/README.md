# Scripts

Operator scripts for devcontainer lifecycle, AWS authentication, Terragrunt
orchestration, and local Kind cluster management.

| Script | Context | Purpose |
|--------|---------|---------|
| [mfa-session.sh](mfa-session.md) | Host | Write devcontainer AWS credentials |
| `operator-profile.sh` | Host | Explicitly write non-secret operator role/MFA mappings from Terraform outputs |
| [container-init.sh](container-init.md) | Container | Devcontainer setup and cluster reconnect |
| [terragrunt-stack.sh](terragrunt-stack.md) | Host or container | Run Terragrunt stacks (`operators-iam`, `csoc-cluster-core`, `spoke-fleet-update`) |
| [kind-csoc.sh](kind-csoc.md) | Host | Local Kind CSOC cluster lifecycle |
| [ssm-repo-secrets/](ssm-repo-secrets/README.md) | Host | Push GitHub App credentials to AWS Secrets Manager |

## Typical Order

```
# 1. One-time: review and apply operator IAM
bash scripts/terragrunt-stack.sh operators-iam plan
# Apply only after review.

# 2. After apply, write structured non-secret profile data
bash scripts/operator-profile.sh

# 3. Each session: select a role and write temporary credentials
bash scripts/mfa-session.sh <MFA_CODE>

# 4. Open devcontainer (VS Code Dev Containers: Reopen in Container)
#    container-init.sh runs automatically

# 5. Push repo secrets (before fleet apply)
bash scripts/ssm-repo-secrets/generate-ssm-payload.sh
bash scripts/ssm-repo-secrets/push-ssm-secrets.sh

# 6. Deploy infrastructure
bash scripts/terragrunt-stack.sh csoc-cluster-core apply
TG_SPOKE_ALIAS=spoke1 bash scripts/terragrunt-stack.sh spoke-fleet-update apply
```
