---
description: 'Compatibility shim for Terraform and Terragrunt guidance; canonical rules live in terraform/AGENTS.md and terragrunt/AGENTS.md'
applyTo: "terraform/**,terragrunt/**"
---

# Terraform and Terragrunt Guidance

Read `terraform/AGENTS.md` or `terragrunt/AGENTS.md` first. This file exists for
Copilot compatibility.

Terragrunt orchestrates environments and dependency ordering. Terraform
implements reusable modules.

Rules:

- AWS foundation modules must not use Kubernetes or Helm providers.
- In-cluster bootstrap modules target an existing named cluster.
- Preserve migration phases in `plan/migration-roadmap.md`.
- Keep the compatibility wrapper until the module split and state migration are
  complete.
- Use Terragrunt dependency outputs for role ARN and cluster metadata handoff.

Do not commit secrets, real account IDs, ARNs with account IDs, tfstate, tfplan
files, generated `.terragrunt-stack` content, outputs, or local credentials.
