# AGENTS.md

## Project Overview

gen3-kro is an EKS Cluster Management Platform. A CSOC control-plane cluster
uses Argo CD, KRO, and ACK controllers to reconcile Gen3 infrastructure across
AWS spoke accounts.

The current architecture plan lives in `plan/`. Treat those files as the source
of truth when implementing the separation of function:

- Terragrunt orchestrates environments and dependency ordering.
- Terraform implements reusable modules.
- AWS foundation modules must not use Kubernetes or Helm providers.
- In-cluster bootstrap modules target an existing named cluster.
- Argo CD, KRO, and ACK own post-bootstrap reconciliation.

## Instruction Precedence

Read the nearest `AGENTS.md` before editing a subtree. More specific AGENTS
files override this root file for their paths. `.github` instruction files are
compatibility shims for Copilot; do not treat them as more authoritative than
AGENTS.md or `plan/*.md`.

## Safety Rules

Never commit secrets, real AWS account IDs, ARNs with account IDs, access keys,
session tokens, private keys, tfstate, tfplan files, generated `.terragrunt-stack`
content, `outputs/`, or local credential artifacts. Use placeholders in docs and
runtime injection for real values.

Do not run Terraform/Terragrunt apply or destroy commands unless the user
explicitly asks for execution. For this repo, infrastructure mutation must be
deliberate, reviewed, and environment-specific.

## Development Workflow

- Use `rg` for search.
- Keep edits scoped to the subsystem you are changing.
- Preserve the migration phases in `plan/migration-roadmap.md`; do not skip the
  compatibility-wrapper or state-migration phases.
- Keep generated artifacts out of tracked source.
- Use ASCII in new docs unless a file already requires non-ASCII.

## Validation Commands

Run the narrowest applicable checks:

```bash
git diff --check
terraform fmt -check -recursive terraform/
terragrunt hcl format --check
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml
```

For AGENTS/instruction-only changes, `git diff --check` plus the explicit
search commands in the relevant plan are sufficient.

