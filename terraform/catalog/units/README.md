# Terragrunt unit catalog

Unit templates connect live stack values to Terraform modules. A unit may
generate backend, provider, version, or root-module files inside Terragrunt's
ignored `.terragrunt-stack` directory. Generated files are disposable and must
not be edited or committed.

| Unit | Module | Dependency/contract |
| --- | --- | --- |
| `aws-csoc-operator-iam` | `aws-csoc-operator-iam` | Independent prerequisite IAM unit. |
| `aws-csoc-cluster` | `aws-csoc-cluster` | Reads explicit operator EKS entries from `aws-csoc-operator-iam`. |
| `aws-csoc-controller-iam` | `aws-csoc-controller-iam` | Reads cluster name, OIDC issuer, and OIDC provider ARN from `aws-csoc-cluster`. |
| `gitops-argocd-install` | `gitops-argocd-install` | Uses cluster endpoint/CA and controller IAM outputs; configures Kubernetes and Helm providers. |
| `aws-spoke-access-iam` | `aws-spoke-access-iam` | Reads controller and approved operator ARNs and runs with the selected spoke provider. |
| `aws-csoc-to-spoke-access` | `aws-csoc-to-spoke-access` | Reads selected spoke output plus controller IAM remote state. |
| `gitops-argocd-bootstrap` | `gitops-argocd-bootstrap` | Uses cluster, controller IAM, Argo CD install state, and spoke-access ordering. |

The live stacks own concrete paths and state keys. Cross-stack contracts use
fixed S3 keys because generated directories are local and ephemeral. Dependency
mocks are allowed only for the explicitly configured `init`, `validate`, `plan`,
and `state` command names; they are never valid deployed outputs and are not
allowed for `apply` or `destroy`.

To use or troubleshoot a unit, start from the corresponding live stack README
under [`../../../terragrunt/live/aws`](../../../terragrunt/live/aws/README.md).
The repository wrapper generates the stack before running a selected unit, so
there is normally no reason to invoke a catalog unit directly.
