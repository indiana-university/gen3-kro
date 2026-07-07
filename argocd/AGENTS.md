# AGENTS.md

## Scope

Argo CD owns post-bootstrap reconciliation: controllers, RGDs, multi-account
wiring, and per-spoke KRO instances.

## GitOps Boundary

- Terraform may create the first Argo CD install and bootstrap ApplicationSet.
- After bootstrap, keep continuous resources in Argo CD, not Terraform.
- `argocd/bootstrap/` contains entry-point ApplicationSets.
- `argocd/csoc/controllers/` contains controller values and cluster-type
  overrides.
- `argocd/csoc/helm/` contains charts for controller ApplicationSets,
  multi-account wiring, and KRO instance rendering.
- `argocd/spokes/<spoke>/infrastructure-values.yaml` is the per-spoke values
  file. Use this spelling exactly.

## Validation

```bash
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml
```

## Security

Do not commit Kubernetes Secrets with real values, real account IDs, ARNs with
account IDs, generated outputs, tfstate, `.terragrunt-stack` content, or local
credential artifacts.

