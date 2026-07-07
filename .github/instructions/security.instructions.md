---
description: 'Compatibility shim for security guidance; canonical rules live in AGENTS.md and scoped AGENTS.md files'
applyTo: "**"
---

# Security Guidance

Never commit:

- Real AWS account IDs.
- ARNs containing real account IDs.
- AWS access keys, secret keys, or session tokens.
- Private keys or certificates.
- Passwords, API tokens, or Kubernetes Secrets with real values.
- Terraform state, plans, generated `.terragrunt-stack` content, outputs, or
  local credential artifacts.

Use placeholders in docs, gitignored local config for environment-specific
values, and runtime injection or AWS Secrets Manager for real secrets.

Before destructive infrastructure actions, confirm the target environment and
ensure the user explicitly requested the operation.
