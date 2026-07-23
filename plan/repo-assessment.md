# Repository Assessment

## Current implementation

The repository now exposes seven independently stateful Terraform boundaries.
Each Terragrunt unit has exactly one same-named root module:

| Unit and module | Responsibility | State key |
| --- | --- | --- |
| `aws-csoc-operator-iam` | Existing-user MFA and multi-role operator access | `prereq/aws-csoc-operator-iam/terraform.tfstate` |
| `aws-csoc-cluster` | CSOC VPC and EKS foundation | `csoc/aws-csoc-cluster/terraform.tfstate` |
| `aws-csoc-controller-iam` | ACK, Argo CD, KRO, and External Secrets identities | `csoc/aws-csoc-controller-iam/terraform.tfstate` |
| `gitops-argocd-install` | Argo CD namespace, service accounts, and Helm installation | `csoc/gitops-argocd-install/terraform.tfstate` |
| `aws-spoke-access-iam` | Per-spoke workload roles trusted by exact CSOC principals | `spokes/<alias>/aws-spoke-access-iam/terraform.tfstate` |
| `aws-csoc-to-spoke-access` | CSOC policy granting access to exact spoke role ARNs | `csoc/aws-csoc-to-spoke-access/terraform.tfstate` |
| `gitops-argocd-bootstrap` | Repository/cluster secrets and the bootstrap ApplicationSet | `csoc/gitops-argocd-bootstrap/terraform.tfstate` |

The top-level stacks are `operators-iam`, `csoc-cluster-core`, and
`spoke-fleet-update`.
Terragrunt owns configuration, dependency ordering, generated unit paths, and
state keys. Terraform modules own reusable resource implementations. AWS
foundation modules do not use Kubernetes or Helm providers.

## Deployment status

Live backend inspection confirmed that only operator IAM was deployed. Its
state now uses `prereq/aws-csoc-operator-iam/terraform.tfstate`; the other six
boundaries start directly at their canonical keys.

The canonical `infrastructure-admin` role and permission policy exist. The
aggregate IAM-user assume policy is pending because the current retired-role
session lacks `iam:PutUserPolicy`. The retired role remains live until an
authorized session completes that policy and verifies a fresh MFA login. The
IAM user itself is external and the registered MFA device remains unchanged.

## Target operator model

`aws-csoc-operator-iam` accepts existing users and independently enabled role
functions. Trust policies list exact user or external principal ARNs. Human
roles require MFA, and each user receives one aggregate assume-role policy
containing only that user's assigned role ARNs.

The initial functions are:

- `infrastructure-admin`: existing infrastructure provisioning permissions,
  exact configured spoke role ARNs, and `AmazonEKSClusterAdminPolicy`.
- `platform-operator`: identity, EKS discovery, and operational log reads, plus
  `AmazonEKSAdminPolicy`. It remains disabled until it has a principal.

The cluster consumes enabled operator-role outputs as explicit EKS access
entries and disables implicit cluster-creator administration. EKS access
policies provide Kubernetes authorization; they do not add AWS IAM
permissions. See the
[AWS EKS access-policy reference](https://docs.aws.amazon.com/eks/latest/userguide/access-policy-permissions.html).

## Migration constraints

- The existing MFA device and physical name must remain unchanged.
- The retired role, role policy, and user policy remain only until the
  authorized IAM completion gate succeeds.
- Local profile files are not managed by Terraform. Explicit scripts produce
  operator-local material.
- Spoke trust uses exact approved operator role ARNs from operator state. It
  has no account-root or wildcard devcontainer exception.
- The historical backend key is no longer operated.

## Remaining live checks

Use an authorized IAM-user or administrator session to review and apply the
final operators-IAM plan. It must preserve the user and MFA device, create the
missing aggregate user policy, and remove exactly the three retired IAM
objects. Then verify a fresh MFA session and all three renamed stack plans.
