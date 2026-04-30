---
name: security-audit
description: 'Run a security audit on gen3-kro — check for secrets, overly broad IAM, and misconfigurations'
agent: agent
tools: ['search/codebase', 'search', 'terminalCommand']
---

# Security Audit for gen3-kro

## Scope

Perform a comprehensive security review of the repository, covering:

1. **Secrets exposure** — scan all YAML, JSON, shell scripts, and Terraform files for:
   - AWS Account IDs (12-digit numbers)
   - AWS Access Key IDs (`AKIA...`) or Secret Keys
   - ARNs containing real account IDs
   - Private keys, passwords, or tokens

2. **IAM least privilege** — review:
   - `iam/` directory inline policies for wildcard actions or resources
   - ACK IAM role trust policies in RGDs for overly broad conditions
   - IRSA role bindings in `argocd/addons/addons.yaml`

3. **S3 security** — verify all S3 bucket RGD templates have:
   - `blockPublicAcls: true`
   - `blockPublicPolicy: true`
   - `ignorePublicAcls: true`
   - `restrictPublicBuckets: true`
   - Server-side encryption enabled

4. **Network exposure** — review ACK SecurityGroup resources in RGDs:
   - No `0.0.0.0/0` on inbound rules except ALB port 443
   - All database security groups have source-SG rules only

5. **GitIgnore coverage** — confirm `.gitignore` covers:
   - `config/*.json` (except examples)
   - `**/*.auto.tfvars.json`
   - `**/secrets/*`
   - `**/outputs/**`

## Output Format

Report findings as:
```
SEVERITY | File | Line | Finding | Recommended Fix
```

Severity levels: CRITICAL (block commit), HIGH (fix before next PR), MEDIUM (track), LOW (informational)

Reference `.github/instructions/security.instructions.md` for rules.
