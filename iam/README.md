# IAM Reference

Stores IAM policy scaffolding that Terragrunt/Terraform can consume when generating pod identity roles.

- `gen3-kro/hub/argocd/recommended-inline-policy`: Baseline inline policy statement ArgoCD uses when assuming hub roles.
- `gen3-kro/hub/acks/`: Placeholder path reserved for ACK controller policy documents (checked out from private Git when configured).

When `live/aws/.../terragrunt.hcl` is executed with `iam_git_repo_url` pointing at a private repository, these paths are used as the merge point for inline policies.

