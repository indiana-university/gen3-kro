---
description: 'Compatibility shim for Dockerfile and devcontainer guidance; canonical rules live in .devcontainer/AGENTS.md'
applyTo: "Dockerfile,.devcontainer/**"
---

# Dockerfile and Devcontainer Guidance

Read `.devcontainer/AGENTS.md` first. This file exists for Copilot
compatibility.

The devcontainer is a reproducible operator toolchain, not the deployment
orchestrator. Keep tool versions pinned in the Dockerfile, mount only
`~/.aws/jayadeyemi` as read-only, do not mount host `~/.kube`, and do not
configure lifecycle commands that auto-apply infrastructure by default.

Do not commit secrets, real account IDs, ARNs with account IDs, generated
outputs, tfstate, `.terragrunt-stack` content, or local credential artifacts.
