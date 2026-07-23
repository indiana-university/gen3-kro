# gitops-argocd-install unit

Terragrunt wrapper for the
[`gitops-argocd-install` module](../../modules/gitops-argocd-install/README.md). It
generates the S3 backend plus Kubernetes and Helm providers authenticated to the
CSOC cluster, reads dependencies from `../aws-csoc-cluster` and
`../aws-csoc-controller-iam`, and stores state at
`csoc/gitops-argocd-install/terraform.tfstate`.

## Architecture

```text
Stage 1 - prerequisite modules                  Stage 2 - target module

┌─ Unit: aws-csoc-cluster ─────────────────┐        ┌─ Unit: gitops-argocd-install ──────────┐
│                                      │        │                                 │
│ ┌─ Module: aws-csoc-cluster ───────┐ │        │ ┌─ Module: gitops-argocd-install ┐ │
│ │                                  ├─┼────────┼→┤                             │ │
│ └──────────────────────────────────┘ │        │ │                             │ │
│                                      │        │ │                             │ │
└──────────────────────────────────────┘        │ │                             │ │
                                                │ │                             │ │
                                                │ │                             │ │
┌─ Unit: aws-csoc-controller-iam ──────────┐        │ │                             │ │
│                                      │        │ │                             │ │
│ ┌─ Module: aws-csoc-controller-iam ┐ │        │ │                             │ │
│ │                                  ├─┼────────┼→┤                             │ │
│ └──────────────────────────────────┘ │        │ └─────────────────────────────┘ │
│                                      │        │                                 │
└──────────────────────────────────────┘        └─────────────────────────────────┘
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Direct Terragrunt dependencies: `aws-csoc-cluster`, `aws-csoc-controller-iam`.
- Requires network reachability and `aws eks get-token` access to the cluster.
- Live owner: [`csoc-cluster-core`](../../../terragrunt/live/aws/csoc-cluster-core/README.md).
