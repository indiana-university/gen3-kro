---
name: gen3-security-scan
description: 'Security audit for gen3-kro — scans for hardcoded secrets, overly permissive IAM policies, public S3 buckets, unencrypted resources, and OWASP Top 10 misconfigurations in KRO RGDs, Terraform, shell scripts, and ArgoCD YAML. Use when: user asks for a security review, asks to check for secrets, asks to audit IAM policies, asks to verify security posture, or mentions OWASP.'
allowed-tools: Bash
---

# gen3-kro Security Scan

Perform a targeted security audit of gen3-kro files, focusing on the patterns most likely to be problematic in this codebase.

## Scan 1 — Hardcoded secrets and credentials

```bash
# AWS Access Keys
grep -rn 'AKIA[0-9A-Z]\{16\}' \
  --include='*.yaml' --include='*.yml' --include='*.json' --include='*.sh' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' --exclude-dir='outputs' \
  /workspaces/gen3-kro/ 2>/dev/null | grep -v '#' | grep -v 'EXAMPLE\|example\|SAMPLE'

# AWS Account IDs (12-digit numbers in non-placeholder contexts)
grep -rn '\b[0-9]\{12\}\b' \
  --include='*.yaml' --include='*.yml' --include='*.json' --include='*.sh' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' --exclude-dir='outputs' \
  /workspaces/gen3-kro/ 2>/dev/null \
  | grep -v '123456789012\|000000000000\|#.*[0-9]\{12\}'

# Private keys
grep -rn 'BEGIN.*PRIVATE KEY\|BEGIN RSA PRIVATE' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null

# Hardcoded passwords
grep -rni 'password\s*=\s*["\x27][^"\x27]\{4,\}["\x27]\|secret\s*=\s*["\x27][^"\x27]\{4,\}["\x27]' \
  --include='*.yaml' --include='*.tf' --include='*.sh' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null \
  | grep -v 'secretsmanager\|SecretString\|secretRef\|secretName\|secret_key\s*=\s*""'
```

## Scan 2 — IAM wildcard resources (A01 Broken Access Control)

```bash
# Wildcard resources in IAM policies
grep -rn '"Resource":\s*"\*"' \
  --include='*.json' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/iam/ 2>/dev/null

# Wildcard resources in RGDs/Terraform
grep -rn 'resources:\s*\["\*"\]\|resource:\s*"*"' \
  --include='*.yaml' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null
```

## Scan 3 — Public S3 / networking misconfigs (A05 Security Misconfiguration)

```bash
# S3 public access — look for missing BlockPublicAcls
grep -rn 'blockPublicAcls\|block_public_acls' \
  --include='*.yaml' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null | grep -i 'false'

# Security groups with 0.0.0.0/0 ingress (acceptable for 80/443, flag others)
grep -rn '0\.0\.0\.0/0' \
  --include='*.yaml' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null
```

## Scan 4 — Unencrypted resources (A02 Cryptographic Failures)

```bash
# RDS without encryption
grep -rn 'storageEncrypted\|storage_encrypted' \
  --include='*.yaml' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null | grep -i 'false'

# S3 without server-side encryption config
# Look for BucketEncryption presence
grep -rn 'serverSideEncryptionConfiguration\|server_side_encryption_configuration' \
  --include='*.yaml' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/ 2>/dev/null | head -20
```

## Scan 5 — Shell script injection risks (A03 Injection)

```bash
# Variables used unquoted in shell commands
grep -rn '\$[A-Z_]*[^"]' \
  --include='*.sh' \
  --exclude-dir='.git' --exclude-dir='references' \
  /workspaces/gen3-kro/scripts/ 2>/dev/null \
  | grep -v '#' | grep -v '"\$\|\\$\|\${' | head -20

# Missing set -euo pipefail
for f in /workspaces/gen3-kro/scripts/*.sh; do
  head -3 "$f" | grep -q 'set -euo pipefail' || echo "MISSING set -euo pipefail: $f"
done
```

## Scan 6 — ARNs containing account IDs in committed files

```bash
# ARNs with embedded 12-digit account IDs (not 123456789012 placeholder)
grep -rn 'arn:aws:[a-z0-9-]*:[a-z0-9-]*:[0-9]\{12\}:' \
  --include='*.yaml' --include='*.yml' --include='*.json' --include='*.tf' \
  --exclude-dir='.git' --exclude-dir='references' --exclude-dir='outputs' \
  /workspaces/gen3-kro/ 2>/dev/null \
  | grep -v '123456789012'
```

## Output Format

For each scan, report:
- **PASS** — no issues found
- **WARN** — potential issue, needs human review
- **FAIL** — definite security problem, must be fixed before commit

Present a summary table at the end:

```
SECURITY SCAN RESULTS — gen3-kro
══════════════════════════════════════════════════
Scan 1: Hardcoded secrets     PASS / WARN / FAIL
Scan 2: IAM wildcards          PASS / WARN / FAIL
Scan 3: Public S3/networking   PASS / WARN / FAIL
Scan 4: Unencrypted resources  PASS / WARN / FAIL
Scan 5: Shell injection        PASS / WARN / FAIL
Scan 6: ARNs with account IDs  PASS / WARN / FAIL
══════════════════════════════════════════════════
OVERALL: PASS / ACTION REQUIRED
```

For each WARN or FAIL, provide the file path, line number, and recommended fix.
