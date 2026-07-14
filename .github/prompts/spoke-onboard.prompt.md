---
description: Add a spoke to the Terragrunt fleet and GitOps values
---

# Onboard A Spoke

Inputs:

- Spoke alias: `${input:spokeName}`
- AWS profile: `${input:awsProfile}`
- AWS region: `${input:region:e.g. us-east-1}`
- AWS account ID: `${input:accountId}`
- Hostname: `${input:hostname:e.g. myapp.example.com}`

## Changes

1. Add the enabled spoke and provider details to the environment's ignored
   `config/shared.auto.tfvars.json`. Never commit the real account ID.
2. Create `iam/${input:spokeName}/ack/inline-policy.json` only when the default
   ACK policy is insufficient.
3. Create `argocd/spokes/${input:spokeName}/` using
   `argocd/spokes/spoke1/` as the current schema reference. Keep only values and
   placeholders in tracked files; do not add secrets.
4. Render the fleet stack with `TG_SPOKE_ALIAS=${input:spokeName}` and review
   plans in this order:

```bash
TG_SPOKE_ALIAS=${input:spokeName} bash terragrunt/live/aws/fleet/stack.sh plan spoke-iam
TG_SPOKE_ALIAS=${input:spokeName} bash terragrunt/live/aws/fleet/stack.sh plan csoc-spoke-access
TG_SPOKE_ALIAS=${input:spokeName} bash terragrunt/live/aws/fleet/stack.sh plan argocd-gitops-bootstrap
```

Do not apply automatically. Confirm that only the selected spoke IAM state,
CSOC spoke-access state, and GitOps bootstrap state change.
