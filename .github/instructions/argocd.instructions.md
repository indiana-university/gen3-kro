---
description: 'Compatibility shim for Argo CD, Helm, and GitOps guidance; canonical rules live in argocd/AGENTS.md'
applyTo: "argocd/**"
---

# Argo CD Guidance

Read `argocd/AGENTS.md` first. This file exists for Copilot compatibility.

Current layout:

- `argocd/bootstrap/`: entry-point ApplicationSets.
- `argocd/csoc/controllers/`: controller values plus `eks` and `kind` overrides.
- `argocd/csoc/helm/`: charts for controller ApplicationSets, multi-account
  wiring, and KRO instance rendering.
- `argocd/csoc/kro/`: plain YAML ResourceGraphDefinitions.
- `argocd/spokes/<spoke>/infrastructure-values.yaml`: per-spoke KRO instance
  values.

Terraform may seed Argo CD and the first bootstrap ApplicationSet. Continuous
controllers, RGDs, multi-account wiring, and spoke instances remain owned by
Argo CD.

Do not commit secrets, real account IDs, ARNs with account IDs, generated
outputs, tfstate, `.terragrunt-stack` content, or local credential artifacts.
