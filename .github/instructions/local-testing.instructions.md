---
description: 'Compatibility shim for local CSOC Kind workflow guidance'
applyTo: "scripts/kind-csoc.sh,scripts/kind-config.yaml,argocd/csoc/**,argocd/spokes/**,config/**"
---

# Local CSOC Guidance

Use `scripts/kind-csoc.sh` for the host-based Kind CSOC workflow. It reuses the
same Argo CD bootstrap model as EKS, but Kind injects AWS credentials into the
`ack` namespace because IRSA is unavailable.

Typical non-destructive inspection:

```bash
bash scripts/kind-csoc.sh status
bash scripts/reports/kro-status-report.sh
```

Credential renewal:

```bash
bash scripts/mfa-session.sh <MFA_CODE>
bash scripts/kind-csoc.sh inject-creds
```

Do not commit generated local config, Kubernetes Secrets, real account IDs, ARNs
with account IDs, credentials, outputs, tfstate, or `.terragrunt-stack` content.
