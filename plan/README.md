# CSOC Provisioning Separation Plan

This directory is the architectural source of truth for the implemented
Terragrunt/Terraform separation and its live migration.

## Operating decision

Terragrunt orchestrates the three environments and seven independently
stateful units. Terraform implements one same-named root module per unit. AWS
foundation modules use only AWS providers; the two GitOps bootstrap modules
target an existing cluster through Kubernetes and Helm providers.

The canonical boundaries are:

```text
aws-csoc-operator-iam
aws-csoc-cluster
aws-csoc-controller-iam
gitops-argocd-install
aws-spoke-access-iam
aws-csoc-to-spoke-access
gitops-argocd-bootstrap
```

After bootstrap, Argo CD, KRO, and ACK own continuous reconciliation.

## Documents

| Document | Purpose |
| --- | --- |
| [repo-assessment.md](repo-assessment.md) | Implemented ownership, deployment baseline, operator model, and live checks. |
| [target-operating-model.md](target-operating-model.md) | Canonical contracts, data flow, names, and deployment order. |
| [migration-roadmap.md](migration-roadmap.md) | Backend migration, parallel IAM cutover, cleanup, and acceptance gates. |

## Migration principle

Only the deployed operator state changes backend key. Its old resources first
move to transitional addresses while a new `infrastructure-admin` role is
created in parallel. The old role is retired only after a fresh new-role
session succeeds. The other six boundaries begin at canonical state keys after
the live backend confirms their old states are absent or empty.
