# Target Operating Model

## Design Principles

- Terragrunt owns environments and dependency ordering.
- Terraform owns reusable resource modules.
- Terraform AWS modules do not reach into Kubernetes.
- Terraform in-cluster modules assume the cluster already exists and is named.
- Argo CD owns continuous reconciliation after the first bootstrap.
- KRO plus ACK own spoke infrastructure and Gen3 application infrastructure.
- Shell scripts provide operator ergonomics, not hidden orchestration state.

## Proposed Module Layout

```text
terraform/catalog/modules/
  aws-csoc-foundation/          # AWS-only VPC, EKS, CSOC IAM, OIDC, outputs
  csoc-in-cluster-bootstrap/    # K8s/Helm bootstrap into an existing named cluster
  aws-spoke/                    # Existing spoke ACK workload roles
  developer-identity/           # Existing personal/devcontainer identity
  argocd-bootstrap/             # Retained as a csoc-in-cluster-bootstrap submodule
  csoc-cluster/                 # Compatibility wrapper until state migration

terragrunt/live/aws/csoc/
  terragrunt.stack.hcl          # Orchestrates all CSOC units and dependencies
```

The current `terraform/catalog/modules/aws-csoc` can be split rather than
rewritten. Move AWS-only resources into `aws-csoc-foundation`; move
`kubernetes_namespace_v1`, Argo CD service accounts, `helm_release.argocd`, repo
secrets, cluster secrets, fleet secrets, and bootstrap Helm release into the
in-cluster module.

## Terragrunt Unit Responsibilities

| Unit | Depends on | Creates | State key |
| --- | --- | --- | --- |
| `developer_identity` | none | Devcontainer role, optional MFA device, user assume policy | `iam-setup/developer-identity/terraform.tfstate` |
| `csoc_foundation` | optional `developer_identity` | CSOC VPC, EKS, OIDC, CSOC ACK role, Argo CD role, optional capability roles | `csoc/foundation/terraform.tfstate` |
| `spoke_iam` | `csoc_foundation` | Per-spoke ACK workload roles with trust to exact CSOC role ARN where possible | `csoc/spoke-iam/terraform.tfstate` |
| `csoc_in_cluster_bootstrap` | `csoc_foundation`, `spoke_iam` | Argo CD install, repo secrets, cluster/fleet secrets, bootstrap ApplicationSet | `csoc/in-cluster-bootstrap/terraform.tfstate` |

This order removes the current reason to create spoke roles before the CSOC role
exists. The initial CSOC cluster can be created without controllers. Then spoke
IAM can trust the actual CSOC source role. Then Argo CD can deploy ACK/KRO with
the needed cross-account roles already present.

## Terraform Module Boundaries

### `aws-csoc-foundation`

Should create:

- VPC, public/private subnets, route tables, NAT configuration.
- EKS cluster and node/Auto Mode configuration.
- OIDC provider.
- CSOC ACK source IAM role.
- Argo CD IAM role for spoke access and AWS reads.
- External Secrets pod identity role if it is a CSOC-cluster foundation concern.
- Optional AWS-managed EKS capability roles/resources.
- Outputs needed by downstream units: cluster name, endpoint, CA, OIDC issuer,
  OIDC provider ARN, CSOC account ID, role ARNs, baseline cluster secret labels
  and annotations.

Should not create:

- Kubernetes namespaces.
- Kubernetes service accounts.
- Helm releases.
- Argo CD cluster/repository secrets.
- Local workstation files.

### `csoc-in-cluster-bootstrap`

Should accept either direct cluster connection outputs or just
`cluster_name`/`region` plus `data.aws_eks_cluster` and
`data.aws_eks_cluster_auth`.

Should create:

- Argo CD namespace.
- Argo CD service accounts with role annotations.
- Argo CD Helm release.
- Argo CD repository secrets from Secrets Manager data.
- CSOC cluster secret and per-spoke fleet cluster secrets.
- First bootstrap ApplicationSet.

Should not create:

- VPC/EKS/IAM foundation resources.
- Spoke IAM roles.
- Gen3/KRO infrastructure instances.

## GitOps Boundary

After `csoc-in-cluster-bootstrap`, reconciliation belongs to Argo CD:

- `argocd/bootstrap/csoc-controllers.yaml` deploys KRO, ACK, External Secrets.
- `argocd/bootstrap/csoc-kro.yaml` deploys RGDs from plain YAML.
- `argocd/bootstrap/multi-account.yaml` deploys namespace/CARM/secret-writer
  wiring.
- `argocd/bootstrap/fleet-instances.yaml` deploys per-spoke KRO instances.

Do not move these resources into Terraform. Terraform should only seed the
control loop.

## Config Model

Keep one human-editable environment file only if it gets a schema and typed
projections. Recommended direction:

```text
config/environments/<env>.json        # human-edited source
outputs/generated/<env>/foundation.tfvars.json
outputs/generated/<env>/spoke-iam.json
outputs/generated/<env>/bootstrap.tfvars.json
```

Terragrunt can read the source config and pass narrowed inputs to each unit.
Terraform roots should not need sink variables for keys they do not consume.

## Operator Entry Points

Recommended commands:

```bash
bash scripts/mfa-session.sh <MFA_CODE>
cd terragrunt/live/aws/csoc
terragrunt stack run plan
terragrunt stack run apply
bash scripts/container-init.sh setup connect
```

Devcontainer defaults should become `setup connect` or just `setup`. Applying
infrastructure should be explicit.

## State and Locking

Use separate state per unit. Add state locking through the selected backend
standard, either S3 lockfile support or DynamoDB locking. Keep state keys stable
and document import/move steps before splitting the current state.

## IAM Trust Target

Target trust for spoke workload roles:

- Prefer exact `arn:aws:iam::<csoc-account>:role/<csoc-alias>-csoc-role`.
- Keep the devcontainer role trust only if manual cleanup is a required
  operator path.
- If bootstrap still needs wildcard trust during migration, make it temporary
  and track a later hardening step.
