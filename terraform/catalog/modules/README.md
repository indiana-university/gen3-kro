# Terraform module catalog

These modules are composed by the unit templates in
[`../units`](../units/README.md). Provider configuration and remote state belong
to Terragrunt, not to the modules.

| Module | Layer | Owns |
| --- | --- | --- |
| [`aws-csoc-operator-iam`](aws-csoc-operator-iam/README.md) | AWS foundation | MFA-gated multi-role operator access for existing IAM users. |
| [`aws-csoc-cluster`](aws-csoc-cluster/README.md) | AWS foundation | CSOC VPC, subnets, NAT, EKS cluster, and OIDC provider. |
| [`aws-csoc-controller-iam`](aws-csoc-controller-iam/README.md) | AWS foundation | Controller IAM, optional EKS capabilities/access, and External Secrets pod identity. |
| [`aws-spoke-access-iam`](aws-spoke-access-iam/README.md) | AWS spoke foundation | Function-keyed spoke access roles and collision-free policies. |
| [`aws-csoc-to-spoke-access`](aws-csoc-to-spoke-access/README.md) | AWS foundation | Exact assume-role permissions from the ACK controller role to spoke roles. |
| [`gitops-argocd-install`](gitops-argocd-install/README.md) | In-cluster bootstrap | Argo CD namespace, service accounts, and optional self-managed Helm release. |
| [`gitops-argocd-bootstrap`](gitops-argocd-bootstrap/README.md) | In-cluster bootstrap | Repository/cluster secrets and the first bootstrap ApplicationSet. |

## Conventions

- Inputs and outputs are declared in each module's `variables.tf` and
  `outputs.tf`; those files are the machine-enforced contract.
- Opaque `*_ready_token` values express ordering only. Consumers must use named
  outputs for resource data.
- Account IDs, role ARNs, credentials, and secret values are runtime inputs or
  data-source results. Examples use placeholders only.
- In-cluster resources and secret payloads are recorded in Terraform state.
  Restrict access to the encrypted remote backend accordingly.
