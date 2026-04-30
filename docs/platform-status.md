# Platform Status — Risks, Limitations & Future Work

Consolidated tracking document for the EKS Cluster Management Platform.

---

## Known Risks

Documented security and operational risks accepted for the current phase.

### R1: `--no-mfa` mode copies long-lived credentials

- **Source**: `scripts/mfa-session.sh` `--no-mfa` path
- **Risk**: Copies static IAM credentials into `~/.aws/eks-devcontainer/credentials` with no automatic expiry.
- **Mitigation**: Intended for trusted development environments only. Credentials are bind-mounted into an isolated directory, limiting exposure. Production workflows must use the MFA path.

### R2: `install.sh` credential check may return false positive

- **Source**: `scripts/install.sh` — `aws sts get-caller-identity` pre-flight check
- **Risk**: `sts:GetCallerIdentity` succeeds even with expired MFA sessions, giving a false "credentials valid" result before Terraform apply fails on actual API calls.
- **Mitigation**: Terraform validates permissions at apply time; the pre-flight check is a convenience gate only.

### R3: KMS policies use `Resource: *` for key creation

- **Source**: `iam/*/ack/inline-policy.json` — `ManageKMSKeysForInfraGraph` statement
- **Risk**: `kms:CreateKey` cannot be scoped by ARN (key doesn't exist yet). Tag conditions (`aws:RequestTag/ManagedBy=ack`) are applied at creation time; if a controller creates a key without the tag, post-creation actions are denied and orphaned keys may result.
- **Mitigation**: Tag conditions prevent modification/deletion of untagged keys. All RGD templates include `ManagedBy: ack` on KMS resources.

---

## Current Limitations

### L1: Diagram SVG exports not generated

- **Files**: `docs/diagrams/*.drawio`
- **Workaround**: Export manually via VS Code draw.io extension → Export As → SVG.

---

## Future Work

### F1: SSO integration for ArgoCD

Replace password-based auth with GitHub/Okta SSO and disable local admin account.

### F2: ESO SecretStore pattern verification

Verify that ESO SecretStore definitions on spoke clusters reference Secrets Manager paths
matching IAM policy conditions (`argocd/*`, `argo-cd/*` prefixes) when ESO deploys.

### F3: Hardened credential validation in `install.sh`

Replace `aws sts get-caller-identity` pre-flight check with a targeted API call
(e.g., `aws eks describe-cluster`) that validates the session has the permissions
actually needed for plan/apply.
