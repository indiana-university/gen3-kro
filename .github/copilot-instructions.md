# gen3-kro Copilot Instructions

These instructions are kept for GitHub Copilot compatibility. The canonical
agent guidance is in `AGENTS.md` and scoped `AGENTS.md` files throughout the
repo. Read the nearest AGENTS file before editing.

## Project Summary

gen3-kro is a CSOC EKS control-plane platform. Terragrunt orchestrates
environments, Terraform implements reusable modules, and Argo CD, KRO, and ACK
own post-bootstrap reconciliation for controllers, RGDs, and spoke
infrastructure.

## Current Architecture Rules

- Follow `plan/README.md`, `plan/target-operating-model.md`, and
  `plan/migration-roadmap.md` for the CSOC separation plan.
- AWS foundation Terraform must not use Kubernetes or Helm providers.
- In-cluster bootstrap Terraform targets an existing named cluster.
- Argo CD owns continuous resources after first bootstrap.
- KRO RGDs remain plain YAML under `argocd/csoc/kro`.
- Per-spoke KRO instance values use
  `argocd/spokes/<spoke>/infrastructure-values.yaml`.

## Safety

Never commit secrets, real AWS account IDs, ARNs with account IDs, access keys,
session tokens, private keys, tfstate, tfplan files, generated
`.terragrunt-stack` content, `outputs/`, or local credential artifacts.

Do not run Terraform/Terragrunt apply or destroy commands unless explicitly
asked by the user.

## Useful Validation

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
