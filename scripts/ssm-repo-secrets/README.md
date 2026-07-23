# ssm-repo-secrets

Stores GitHub App credentials in AWS Secrets Manager so the GitOps bootstrap
Terraform unit can configure ArgoCD repository access.

> **Private repositories only.** If your GitOps repo is public, skip this
> section entirely — ArgoCD can clone public repos without credentials.

## Files

| File | Description |
|------|-------------|
| `config/ssm-repo-secrets/input.json` | GitHub App credentials per repo (gitignored) |
| `config/ssm-repo-secrets/input.json.example` | Template — copy and fill in |
| `outputs/ssm-repo-secrets/output.json` | Generated SSM payload (gitignored) |

## Workflow

```bash
# 1. Copy and populate the input file
cp config/ssm-repo-secrets/input.json.example config/ssm-repo-secrets/input.json

# 2. Generate the SSM payload (fetches GitHub App installation ID via API)
bash scripts/ssm-repo-secrets/generate-ssm-payload.sh

# 3. Push secrets to AWS Secrets Manager
bash scripts/ssm-repo-secrets/push-ssm-secrets.sh [--profile PROFILE] [--region REGION]
```

Step 3 must complete before running
`bash scripts/terragrunt-stack.sh spoke-fleet-update apply` — the GitOps bootstrap unit
reads the secret name from `config/shared.auto.tfvars.json`
(`ssm_repo_secret_names`) and expects the secret to already exist.

## input.json Fields

```json
{
  "repos": [
    {
      "name":                       "eks-cluster-mgmt",
      "ssm_secret_name":            "/gen3-kro-csoc/eks-cluster-mgmt/git-credentials",
      "github_url":                 "github.com",
      "org_name":                   "<YOUR_ORG>",
      "repo_name":                  "<YOUR_REPO>",
      "github_app_id":              "<APP_ID>",
      "github_client_id":           "Iv1.xxxxxxxxxxxx",
      "github_app_private_key_file":"config/ssm-repo-secrets/<app>.pem",
      "github_app_client_secret":   "<CLIENT_SECRET>"
    }
  ]
}
```

Download the `.pem` private key from the GitHub App settings page and place it
in `config/ssm-repo-secrets/`. The file is gitignored.

## generate-ssm-payload.sh

Reads `input.json`, calls the GitHub API to resolve the App installation ID for
each repo, and writes a formatted JSON payload to
`outputs/ssm-repo-secrets/output.json`.

If `input.json` does not exist or contains an empty `repos` list, the script
writes an empty payload and exits successfully (no-op).

## push-ssm-secrets.sh

Reads `outputs/ssm-repo-secrets/output.json` and creates or updates each
secret in AWS Secrets Manager using the AWS CLI. Defaults to the current
`AWS_PROFILE` and `us-east-1`. Override with `--profile` or `--region`.
