---
description: 'Security rules and secret-handling requirements that apply across all files in gen3-kro'
applyTo: "**"
---

# Security Rules

## Never Commit Secrets

**Block** the following from ever appearing in any committed file:

| Type | Pattern | Safe Alternative |
|------|---------|-----------------|
| AWS Account ID | 12-digit number | `123456789012` placeholder in docs |
| AWS Access Key | `AKIA[0-9A-Z]{16}` | IRSA or MFA-assumed role |
| AWS Secret Key | 40-char alphanumeric | IRSA or K8s Secret (gitignored) |
| Private keys | `-----BEGIN ... PRIVATE KEY-----` | Never in git |
| ARNs with account IDs | `arn:aws:...:123456789012:...` | Runtime injection |
| Passwords / tokens | Any hardcoded value | Secrets Manager or K8s Secret |

## gen3-kro Secret Handling

- **EKS CSOC:** ACK uses IRSA — no long-lived keys stored anywhere
- **Local CSOC:** ACK uses K8s Secret `ack-aws-credentials` — created at runtime from
  `~/.aws/credentials`, never committed
- **AWS Account ID:** Injected at runtime via `aws sts get-caller-identity` into the
  ArgoCD cluster Secret annotation — never stored in YAML files or git

## GitIgnore Coverage

The `.gitignore` already covers:
- `*.pem`, `*.ppk`, `**/secrets/*`, `**/secrets.yaml`
- `**/*.tfvars`, `**/*.tfvars.json`, `**/*.auto.tfvars.json`
- `config/*.json` (except `*.example` and `README.md`)
- `**/outputs/**`

## OWASP Top 10 Guidance

When writing any code or configuration:
- **A01 Broken Access Control:** Least-privilege IAM policies; no wildcard `*` resources
- **A02 Cryptographic Failures:** Enable KMS encryption for RDS, S3, EKS secrets
- **A03 Injection:** No string interpolation of user data into shell commands or SQL
- **A05 Security Misconfiguration:** All S3 buckets block public access; no `0.0.0.0/0` ingress
- **A09 Security Logging:** CloudTrail enabled; ACK audit logs via EKS control plane logging

## Reporting Suspected Secrets

If Copilot generates output that contains what appears to be a real credential:
1. Do not commit the file
2. Rotate the credential immediately
3. Verify the `.gitignore` excludes the file type
