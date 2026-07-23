# container-init.sh

Devcontainer lifecycle script. Called automatically by `devcontainer.json`
via `postCreateCommand` (setup) and `postStartCommand` (connect). Each stage
is opt-in via positional flags — with no flags the script is a safe no-op.

## Usage

```bash
bash scripts/container-init.sh setup    # First-time env setup (postCreateCommand)
bash scripts/container-init.sh connect  # Reconnect to existing cluster (postStartCommand)
```

## Stages

### `setup`

Runs once after the container is created:

- Creates required output directories.
- Validates AWS credentials and writes a tiered credential report to
  `outputs/reports/credential-report.txt`.
- Generates `config/local.env` from template if it does not exist.
- Optionally configures MCP and Codex tooling.

### `connect`

Runs on every container start when a cluster already exists:

- Updates `~/.kube/config` with the CSOC cluster endpoint.
- Starts an ArgoCD port-forward (reads password from
  `outputs/argocd-password.txt`).

## Credential Tiers

The `setup` stage checks credentials from most to least secure:

| Tier | Type | Indicator |
|------|------|-----------|
| 1 (best) | MFA assumed-role | `assumed-role` in caller ARN + expiry metadata |
| 2 | Static IAM user | `user/` in caller ARN |
| 3 | Expired | Credentials present but `sts:GetCallerIdentity` fails |
| 4 (none) | Missing | `~/.aws/credentials` not found |

A successful Tier 1 check prints:
```
AWS identity: arn:aws:sts::<account>:assumed-role/<CSOC_ALIAS>-csoc-operator-infrastructure-admin/...
Using temporary credentials (assumed-role) — good
```

## Prerequisites

`~/.aws/jayadeyemi/credentials [badeyemi_tf]` must be written before the
container starts. See [mfa-session.md](mfa-session.md).
