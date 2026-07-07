---
description: 'Compatibility shim for shell script guidance; canonical rules live in scripts/AGENTS.md'
applyTo: "scripts/**"
---

# Script Guidance

Read `scripts/AGENTS.md` first. This file exists for Copilot compatibility.

Scripts provide operator ergonomics and reporting. Use Bash strict mode, quote
variables, keep path resolution portable, and avoid hidden infrastructure
mutation. Apply and destroy actions must be explicit.

Prefer shared credential/config helpers when touching both EKS and Kind
workflows.

Do not commit secrets, real account IDs, ARNs with account IDs, credentials,
outputs, tfstate, or generated `.terragrunt-stack` content.
