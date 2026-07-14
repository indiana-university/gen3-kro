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
- Keep cluster, controller IAM, spoke access, Argo CD install, and GitOps
  bootstrap ownership separate.
- Use Terragrunt dependency outputs within a stack and fixed S3 state outputs
  across stacks.

Do not commit secrets, real account IDs, ARNs with account IDs, tfstate, tfplan
files, generated `.terragrunt-stack` content, outputs, or local credentials.
