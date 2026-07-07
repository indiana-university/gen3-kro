---
description: 'Compatibility shim for KRO ResourceGraphDefinition guidance; canonical rules live in argocd/csoc/kro/AGENTS.md'
applyTo: "argocd/csoc/kro/**,**/*-rg.yaml"
---

# KRO RGD Guidance

Read `argocd/csoc/kro/AGENTS.md` first. This file exists for Copilot
compatibility.

Keep RGDs as plain YAML. Use KRO schema DSL fields, ACK annotations, optional
chaining with `.orValue()`, and bridge ConfigMaps for cross-RGD data. ACK
`readyWhen` checks must validate both resource identity and
`ACK.ResourceSynced == True`.

Version breaking schema changes with a new RGD kind rather than removing or
renaming fields in place.

Do not commit secrets, real account IDs, ARNs with account IDs, generated
outputs, tfstate, `.terragrunt-stack` content, or local credential artifacts.
