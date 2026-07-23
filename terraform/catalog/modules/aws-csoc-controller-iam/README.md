# AWS CSOC controller IAM

AWS-only module for controller identities and optional AWS-managed EKS
capabilities on an existing CSOC cluster. It consumes the cluster name, OIDC
issuer URL, and OIDC provider ARN; it does not install controllers or configure
Kubernetes/Helm providers.

## Managed modes

| Concern | Self-managed behavior | AWS-managed behavior |
| --- | --- | --- |
| ACK | Creates `<csoc_alias>-ack-controller-role` for ACK service accounts when enabled. | Uses the same role, adds EKS access and an `ACK` capability when enabled. |
| KRO | No AWS resource here; Argo CD owns installation. | Creates a capability service role, cluster-admin access entry, and `KRO` capability. |
| Argo CD | Creates an IRSA role for the server and application-controller service accounts when enabled. | Creates a capability service role, cluster-admin access entry, and `ARGOCD` capability. |
| External Secrets | Optional EKS Pod Identity role/association based on `addons.enable_external_secrets`. | Same behavior; independent of the controller mode fields. |

Each capability requires both its matching `*_management_type = "aws_managed"`
and `enable_*_capability = true`. Self-managed roles likewise require the
matching management type and enable flag. Capability deletion uses `RETAIN`, so
review AWS behavior and residual resources before teardown.

The shared ACK source role is a special case: it is created when either
`enable_ack_capability` or `enable_ack_self_managed` is true. The management type
still gates creation of the AWS-managed capability itself. Avoid contradictory
flag/mode combinations even though Terraform can represent them.

The ACK source role trusts the EKS capability service and selected service
accounts through the cluster OIDC provider. The Argo CD self-managed role grants
scoped repository-secret/parameter reads by name pattern plus EKS describe/list.
The External Secrets pod-identity module grants the resource patterns declared
in `external-secrets.tf`, including its current ECR custom policy. Treat policy
changes as security-sensitive.

## Architecture

```text
Prerequisites/Dependencies           IAM resources and optional AWS capabilities for CSOC controllers
┌──────────────────────────────┐    ┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Module: aws-csoc-cluster     │    │ Module: aws-csoc-controller-iam                                                                        │
│ ┌──────────────────────────┐ │    │                                                                                                        │
│ │ IAM OIDC                 │ │    │       ┌─────────────────────┐                ┌────────────────────────────────────┐                    │
│ │ provider                 ├─┼────┼──→┬──→│ ACK source IAM role ├──────────────┬→│ ACK access entry                   │                    │
│ └──────────────────────────┘ │    │   │   └─────────────────────┘              │ └────────────────────────────────────┘                    │
│ ┌──────────────────────────┐ │    │   │                                        │ ┌────────────────────────────────────┐                    │
│ │ CSOC EKS cluster         │ │    │   │                                        ├→│ ACK admin policy association       │                    │
│ └──────────────────────────┘ │    │   │                                        │ └────────────────────────────────────┘                    │
└──────────────────────────────┘    │   │                                        │ ┌────────────────────────────────────┐                    │
                                    │   │                                        └→│ ACK capability (optional)          │                    │
                                    │   │                                          └────────────────────────────────────┘                    │
                                    │   │                                                                                                    │
                                    │   │  ┌───────────────────────┐               ┌────────────────────────────────────┐                    │
                                    │   └─→│ Argo CD IRSA IAM role ├──────────────→│ Argo CD inline IAM policy          │                    │
                                    │      └───────────────────────┘               └────────────────────────────────────┘                    │
                                    │                                                                                                        │
                                    │      ┌──────────────────────┐                ┌────────────────────────────────────┐                    │
                                    │      │ KRO service IAM role ├──────────────┬→│ KRO access entry                   │                    │
                                    │      └──────────────────────┘              │ └────────────────────────────────────┘                    │
                                    │                                            │ ┌────────────────────────────────────┐                    │
                                    │                                            ├→│ KRO admin policy association       │                    │
                                    │                                            │ └────────────────────────────────────┘                    │
                                    │                                            │ ┌────────────────────────────────────┐                    │
                                    │                                            └→│ KRO capability (optional)          │                    │
                                    │                                              └────────────────────────────────────┘                    │
                                    │                                                                                                        │
                                    │      ┌──────────────────────────┐            ┌────────────────────────────────────┐                    │
                                    │      │ Argo CD service IAM role ├──────────┬→│ Argo CD access entry               │                    │
                                    │      └──────────────────────────┘          │ └────────────────────────────────────┘                    │
                                    │                                            │ ┌────────────────────────────────────┐                    │
                                    │                                            ├→│ Argo CD admin policy association   │                    │
                                    │                                            │ └────────────────────────────────────┘                    │
                                    │                                            │ ┌────────────────────────────────────┐                    │
                                    │                                            └→│ Argo CD capability (optional)      │                    │
                                    │                                              └────────────────────────────────────┘                    │
                                    │                                                                                                        │
                                    │   ┌──────────────────────────────────────────────────────────────────────────────────────────────┐     │
                                    │   │ Module: terraform-aws-eks-pod-identity                                                       │     │
                                    │   │                                                                                              │     │
                                    │   │ ┌───────────────────────────────────┐      ┌──────────────────────────────────────────────┐  │     │
                                    │   │ │ External Secrets IAM policy       ├─────→│ Secrets role-policy attachment               │  │     │
                                    │   │ └───────────────────────────────────┘      └──────────────────────────────────────────────┘  │     │
                                    │   │ ┌───────────────────────────────────┐      ┌──────────────────────────────────────────────┐  │     │
                                    │   │ │ Custom ECR IAM policy             ├─────→│ ECR role-policy attachment                   │  │     │
                                    │   │ └───────────────────────────────────┘      └──────────────────────────────────────────────┘  │     │
                                    │   │ ┌───────────────────────────────────┐      ┌──────────────────────────────────────────────┐  │     │
                                    │   │ │ External Secrets pod IAM role     ├─────→│ Pod Identity association                     │  │     │
                                    │   │ └───────────────────────────────────┘      └──────────────────────────────────────────────┘  │     │
                                    │   └──────────────────────────────────────────────────────────────────────────────────────────────┘     │
                                    └────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

This module depends on the `aws-csoc-cluster` unit's outputs for identity binding
to the existing cluster. External Secrets support is delegated to the upstream
`terraform-aws-eks-pod-identity` module when that add-on is enabled.

## Contract

| Input | Default | Meaning |
| --- | --- | --- |
| `csoc_alias` | required | Base name for controller resources. |
| `cluster_name` | required | Existing CSOC EKS cluster. |
| `cluster_oidc_issuer_url` | required | Cluster OIDC issuer used in IRSA conditions. |
| `oidc_provider_arn` | required | IAM OIDC provider trusted by IRSA roles. |
| `argocd_namespace` | `argocd` | Namespace used in Argo CD role trust. |
| `ack_namespace` | `ack` | Namespace used in ACK role trust. |
| `external_secrets_namespace` | `external-secrets` | Pod Identity association namespace. |
| `external_secrets_service_account` | `external-secrets-sa` | Pod Identity service account. |
| `addons` | `{}` | Add-on flags; `enable_external_secrets` controls pod identity creation. |
| `ack_management_type` | `self_managed` | Validated ACK mode: `self_managed` or `aws_managed`. |
| `kro_management_type` | `self_managed` | Validated KRO mode: `self_managed` or `aws_managed`. |
| `argocd_management_type` | `self_managed` | Validated Argo CD mode: `self_managed` or `aws_managed`. |
| `enable_ack_capability` | `false` | Enables the ACK EKS capability when ACK is AWS-managed. |
| `enable_kro_capability` | `false` | Enables the KRO EKS capability when KRO is AWS-managed. |
| `enable_argocd_capability` | `false` | Enables the Argo CD EKS capability when Argo CD is AWS-managed. |
| `enable_ack_self_managed` | `false` | Creates the shared ACK role for self-managed ACK. |
| `enable_argocd_self_managed` | `false` | Creates the Argo CD IRSA role for self-managed Argo CD. |
| `environment` | `control-plane` | Environment tag value. |
| `tags` | `{}` | Additional common resource tags. |

| Output | Meaning |
| --- | --- |
| `ack_controller_role_arn` | Shared ACK controller role ARN, or empty when disabled. |
| `ack_controller_role_name` | Shared ACK controller role name, or empty when disabled. |
| `argocd_controller_role_arn` | Enabled self-managed or AWS-managed Argo CD role ARN. |
| `argocd_controller_role_name` | Enabled self-managed or AWS-managed Argo CD role name. |
| `controller_ready_token` | Ordering-only token covering enabled controller resources. |

[`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf) remain the
machine-enforced contract. AWS-managed capability role ARNs are not public
module outputs.

The live owner is `aws-csoc-controller-iam` in the
[`csoc-cluster-core` stack](../../../../terragrunt/live/aws/csoc-cluster-core/README.md), with
state key `csoc/aws-csoc-controller-iam/terraform.tfstate`.
