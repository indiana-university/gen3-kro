# Argo CD GitOps bootstrap

In-cluster module that seeds the GitOps control loop after Argo CD is available.
It creates:

- Optional Argo CD repository secrets from AWS Secrets Manager.
- One Argo CD cluster secret representing the CSOC cluster.
- One generator-only cluster secret per enabled spoke, pointing back to the in-cluster API server and carrying spoke metadata.
- The first bootstrap ApplicationSet through the local bootstrap Helm chart.

The module does not install Argo CD or reconcile controllers, RGDs, or KRO instances itself.The bootstrapped Argo CD applications own those resources.

Despite its historical name, `ssm_repo_secret_names` contains AWS Secrets Manager secret IDs. It accepts either `{ repos = [{ name, ssm_secret_name }] }` or the legacy map form. Blank entries are ignored, so public repositories need no secret reads. Each secret value must contain Argo CD repository fields such as `url`, `type`, and the GitHub App fields used in `main.tf`.

Cluster labels and annotations are stringified. The module adds the ACK role, spoke account annotations, and `fleet_spokes_json` needed by downstream ApplicationSets. Per-spoke secrets inherit repository annotations and selected
environment/region labels.

## Architecture

```text
Prerequisites/Dependencies                                  ArgoCD GitOps bootstrap resources
                                                            ┌──────────────────────────────────────────────────────────────────────────────┐
┌───────────────────────────────────────────┐               │ Module: gitops-argocd-bootstrap                                              │
│ Data: Existing AWS Secrets Manager        │               │   ┌───────────────────────────────────┐                                      │
│       credentials                         │               │   │ Private repository secrets        │                                      │
│                                           │               │   │                                   │                                      │
│  ┌───────────────────────┐                │               │   │   ┌───────────────────────┐       │                                      │
│  │ Add-ons AWS secret    ├────────────────┼───────────────┼───┼──→┤ Add-ons repo secret   │       │                                      │
│  └───────────────────────┘                │               │   │   └───────────────────────┘       │                                      │
│  ┌────────────────────────┐               │               │   │   ┌────────────────────────┐      │                                      │
│  │ Platform AWS secret    ├───────────────┼───────────────┼───┼──→┤ Platform repo secret   │      │                                      │
│  └────────────────────────┘               │               │   │   └────────────────────────┘      │                                      │
│  ┌───────┐                                │               │   │   ┌───────┐                       │                                      │
│  │ ...   │                                │               │   │   │ ...   │                       │                                      │
│  └───────┘                                │               │   │   └───────┘                       │                                      │
└───────────────────────────────────────────┘               │   └───────────────────────────────────┘                                      │
                                                            │                                                                              │
┌───────────────────────────────────────────┐               │   ┌───────────────────────────────────┐                                      │
│ Module: gitops-argocd-install             │               │   │ Spoke fleet-generator secrets     │                                      │
│                                           │               │   │  — CSOC API                       │                                      │
│  ┌───────────────────────┐                │               │   │   ┌──────────────────┐            │  ┌────────────────────────────────┐  │
│  │ Argo CD namespace     │                │               │   │   │ Spoke 1 secret   │            │  │ Argo CD bootstrap Helm release │  │
│  └───────────────────────┘                │               │   │   └──────────────────┘            │  └────────────────────────────────┘  │
└───────────────────────────────────────────┘               │   │   ┌──────────────────┐            │                                      │
                                                            │   │   │ Spoke 1 secret   │            │                                      │
┌───────────────────────────────────────────┐               │   │   └──────────────────┘            │                                      │
│ Module: aws-csoc-controller-iam           │               │   │   ┌───────┐                       │                                      │
│                                           │               │   │   │ ...   │                       │                                      │
│  ┌───────────────────────┐                │               │   │   └───────┘                       │                                      │
│  │ ACK source IAM role   ├────────────────┼─────────→┐    │   └───────────────────────────────────┘                                      │
│  └───────────────────────┘                │          │    │                                                                              │
└───────────────────────────────────────────┘          │    │                                                                              │
                                                       │    │                                                                              │
┌───────────────────────────────────────────┐          │    │   ┌─────────────────────────────────┐                                        │
│ Module: aws-csoc-cluster                  │          ├────┼──→┤ CSOC Argo CD cluster secret     │                                        │
│                                           │          │    │   └─────────────────────────────────┘                                        │
│  ┌───────────────────────┐                │          │    │                                                                              │
│  │ CSOC EKS cluster      ├────────────────┼─────────→┘    │                                                                              │
│  └───────────────────────┘                │               │                                                                              │
└───────────────────────────────────────────┘               └──────────────────────────────────────────────────────────────────────────────┘
```

The detached guide gives the general deployment direction; it is not a resource-data connector. Solid branches show only consumed data: the CSOC EKS cluster identity and ACK source-role metadata feed the CSOC cluster Secret, and each Secrets Manager credential feeds its matching repository Secret. The Argo CD namespace is an earlier operational prerequisite and contains every managed Kubernetes and Helm resource.

The spoke fleet-generator Secrets and bootstrap Helm release intentionally have no incoming resource-data arrows. Terraform schedules the spoke Secrets after the CSOC cluster Secret and schedules the Helm release after the repository and CSOC cluster Secrets with explicit ordering, but neither destination consumes attributes from those resources. The opaque bootstrap token and `aws-csoc-to-spoke-access` dependency also order deployment without supplying resource data.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Enables all managed secret and bootstrap resources. |
| `cluster_name` | required | CSOC cluster name stored in the Argo CD cluster secret. |
| `argocd_namespace` | `argocd` | Existing namespace receiving bootstrap resources. |
| `ssm_repo_secret_names` | `{ repos = [] }` | AWS Secrets Manager IDs in preferred list or legacy map form. |
| `argocd_cluster_secret_name` | empty | Explicit CSOC secret name; empty derives `<cluster_name>-secret`. |
| `argocd_cluster_labels` | `{}` | Additional cluster-secret labels, converted to strings. |
| `argocd_cluster_annotations` | `{}` | Base cluster and fleet annotations, converted to strings. |
| `ack_controller_role_arn` | empty | ACK controller role exposed to downstream ApplicationSets. |
| `spoke_account_ids` | `{}` | Enabled spoke alias-to-account-ID map. |
| `bootstrap_dependency_token` | empty | Opaque ordering input from the wrapper; not resource data. |

| Output | Meaning |
| --- | --- |
| `git_repository_secret_names` | Logical repository name to Kubernetes Secret name map. |
| `argocd_cluster_secret_name` | Created CSOC cluster-secret name, or `null` when disabled. |
| `spoke_account_ids` | Spoke map used to construct metadata. |
| `cluster_annotations` | Effective CSOC cluster-secret annotations. |
| `bootstrap_applicationset_name` | ApplicationSet name from the bootstrap manifest. |

[`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf) remain the machine-enforced contract. Secret payloads are intentionally not output, but they are stored in Terraform state and Kubernetes Secrets; secure both stores.

The live owner is `gitops-argocd-bootstrap` in the [`spoke-fleet-update` stack](../../../../terragrunt/live/aws/spoke-fleet-update/README.md), with state key `csoc/gitops-argocd-bootstrap/terraform.tfstate`.
