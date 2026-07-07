# AGENTS.md

## Scope

Terraform is the module implementation layer. Terragrunt owns environment
orchestration.

## Module Boundaries

- AWS foundation modules create AWS resources only: VPC, EKS, OIDC, IAM roles,
  optional EKS capabilities, and outputs for downstream units.
- AWS foundation modules must not configure Kubernetes or Helm providers.
- In-cluster bootstrap modules may use Kubernetes and Helm providers, but they
  must target an existing named cluster.
- Do not move Argo CD-managed controllers, RGDs, or KRO instances into
  Terraform. Terraform seeds the control loop only.
- Preserve the current compatibility wrapper during the module-split phase.

## State and Providers

- Keep state split by Terragrunt unit once migrated.
- Do not commit tfstate, plans, `.terraform/`, or generated backend files.
- Prefer provider lockfiles and CI validation for reproducibility.
- Use explicit outputs for dependency handoff rather than re-parsing names in
  downstream modules.

## Security

Never commit secrets, real account IDs, ARNs with account IDs, tfstate,
generated `.terragrunt-stack` content, `outputs/`, or local credential
artifacts.
