# gitops-argocd-bootstrap unit

Terragrunt wrapper for the
[`gitops-argocd-bootstrap` module](../../modules/gitops-argocd-bootstrap/README.md).
It generates the S3 backend plus AWS, Kubernetes, and Helm providers; reads
cluster, controller IAM, and Argo CD install remote state; depends on
`../aws-csoc-to-spoke-access` for the latest spoke-access ordering token; and stores
state at `csoc/gitops-argocd-bootstrap/terraform.tfstate`.

## Architecture

```text
Stage 1 - prerequisite modules                  Stage 2 - target module

┌─ Unit: aws-csoc-cluster ─────────────────┐        ┌─ Unit: gitops-argocd-bootstrap ──────┐
│                                      │        │                                      │
│ ┌─ Module: aws-csoc-cluster ───────┐ │        │ ┌─ Module: gitops-argocd-bootstrap ┐ │
│ │                                  ├─┼────────┼→┤                                  │ │
│ └──────────────────────────────────┘ │        │ │                                  │ │
│                                      │        │ │                                  │ │
└──────────────────────────────────────┘        │ │                                  │ │
                                                │ │                                  │ │
                                                │ │                                  │ │
┌─ Unit: aws-csoc-controller-iam ──────────┐        │ │                                  │ │
│                                      │        │ │                                  │ │
│ ┌─ Module: aws-csoc-controller-iam ┐ │        │ │                                  │ │
│ │                                  ├─┼────────┼→┤                                  │ │
│ └──────────────────────────────────┘ │        │ │                                  │ │
│                                      │        │ │                                  │ │
└──────────────────────────────────────┘        │ │                                  │ │
                                                │ │                                  │ │
                                                │ │                                  │ │
┌─ Unit: gitops-argocd-install ───────────────┐        │ │                                  │ │
│                                      │        │ │                                  │ │
│ ┌─ Module: gitops-argocd-install ─────┐ │        │ │                                  │ │
│ │                                  ├─┼────────┼→┤                                  │ │
│ └──────────────────────────────────┘ │        │ └──────────────────────────────────┘ │
│                                      │        │                                      │
└──────────────────────────────────────┘        └──────────────────────────────────────┘

┌─ Unit: aws-csoc-to-spoke-access ──────────┐
│                                    │
│ ┌─ Module: aws-csoc-to-spoke-access ┐ │
│ │                                │ │
│ └────────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘

Deployment order only (not resource data): aws-csoc-to-spoke-access -> gitops-argocd-bootstrap
```

Nested boxes show composition. Solid arrows show data or reference flow between modules.

## Dependencies

- Direct Terragrunt dependency: `aws-csoc-to-spoke-access`.
- Remote-state dependencies on `aws-csoc-cluster`, `aws-csoc-controller-iam`, and `gitops-argocd-install` state.
- Live owner: [`spoke-fleet-update`](../../../terragrunt/live/aws/spoke-fleet-update/README.md).
