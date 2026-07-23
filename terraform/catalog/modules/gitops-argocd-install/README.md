# Kubernetes Argo CD install

In-cluster bootstrap module for an existing cluster. Terragrunt supplies
Kubernetes and Helm providers authenticated to the named CSOC EKS cluster.

The module creates the Argo CD namespace when any self-managed install,
AWS-managed capability, or downstream GitOps bootstrap needs it. For
self-managed Argo CD it also creates the `argocd-server` and
`argocd-application-controller` service accounts, annotates both with the
supplied IAM role, and installs the pinned Argo CD Helm chart using those
accounts. Additional `argocd_values` are passed to the release.

It does not create EKS/IAM resources, repository secrets, cluster secrets,
ApplicationSets, or continuously managed add-ons.

## Architecture

```text
Prerequisites/Dependencies                  Argo CD namespace and Controller installation
┌─────────────────────────────────────┐    ┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ Module: aws-csoc-cluster            │    │ Module: gitops-argocd-install                                                                 │
│ ┌─────────────────────────────────┐ │    │                                                                                            │
│ │ CSOC EKS cluster                │ │    │   ┌───────────────────┐                    ┌────────────────────────────┐                  │
│ └─────────────────────────────────┘ │    │   │ Argo CD namespace ├──────────────────┬→│ Argo CD service accounts   │                  │
└─────────────────────────────────────┘    │   └───────────────────┘                  │ │ ┌────────────────────────┐ │                  │
                                           │                                          │ │ │ Server service account │ │                  │
┌─────────────────────────────────────┐    │                                          │ │ └────────────────────────┘ │                  │
│ Module: aws-csoc-controller-iam     │    │                                          │ │ ┌────────────────────────┐ │                  │
│ ┌─────────────────────────────────┐ │    │                                          │ │ │ Application-controller │ │                  │
│ │ Argo CD IRSA IAM role           ├─┼────┼─────────────────────────────────────────→│ │ │ service account        │ │                  │
│ └─────────────────────────────────┘ │    │                                          │ │ └────────────────────────┘ │                  │
└─────────────────────────────────────┘    │                                          │ └────────────────────────────┘                  │
                                           │                                          │                                                 │
                                           │                                          └───────────────→┌──────────────────────┐         │
                                           │                                                           │ Argo CD Helm release │         │
                                           │                                                           │ optional             │         │
                                           │                                                           └──────────────────────┘         │
                                           └────────────────────────────────────────────────────────────────────────────────────────────┘
```

The module depends on a live CSOC cluster and, for self-managed mode, the IAM
role exported by `aws-csoc-controller-iam`. It only seeds namespace and Helm
resources; GitOps bootstrap remains a downstream concern.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master switch for namespace and release resources. |
| `csoc_account_id` | required | Account ID stored as namespace metadata. |
| `argocd_namespace` | `argocd` | Namespace to create or reference. |
| `argocd_chart_version` | required | Exact Argo CD Helm chart version. |
| `argocd_chart_repository` | Argo project's Helm repository | Chart repository URL. |
| `argocd_values` | `{}` | Additional values passed to the Helm release. |
| `enable_argocd_self_managed` | `false` | Creates service accounts and the Helm release. |
| `enable_argocd_capability` | `false` | Creates the namespace needed by AWS-managed Argo CD. |
| `argocd_bootstrap_enabled` | `false` | Creates the namespace needed by downstream bootstrap. |
| `argocd_controller_role_arn` | empty | IAM role annotation for Argo CD service accounts. |

| Output | Meaning |
| --- | --- |
| `argocd_namespace` | Effective Argo CD namespace. |
| `argocd_release_name` | Helm release name, or `null` when not installed. |
| `install_ready_token` | Ordering-only namespace/release token. |

[`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf) remain the
machine-enforced contract.

The live owner is `gitops-argocd-install` in the
[`csoc-cluster-core` stack](../../../../terragrunt/live/aws/csoc-cluster-core/README.md), with
state key `csoc/gitops-argocd-install/terraform.tfstate`. Its state contains Kubernetes
and Helm resource data and must be access-controlled.
