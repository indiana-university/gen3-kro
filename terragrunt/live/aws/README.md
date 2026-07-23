# AWS live stacks

The AWS environment is split into three independently operated stacks. Run them
in this order for creation and reverse the infrastructure portions for removal:

```text
Stage 1 - operator IAM   Stage 2 - CSOC cluster core   Stage 3 - spoke fleet update   Stage 4 - continuous reconciliation
Orchestration order: earlier ──────────────────────→ later

operators-iam → csoc-cluster-core → spoke-fleet-update → Argo CD/KRO/ACK reconciliation
```

`operators-iam` establishes operator access. `csoc-cluster-core` creates the
control-plane AWS and initial in-cluster foundation. `spoke-fleet-update` creates spoke IAM,
grants the CSOC controller exact spoke access, and seeds GitOps registration.

## State ownership

| Stack/unit | Stable S3 key |
| --- | --- |
| `operators-iam/aws-csoc-operator-iam` | `prereq/aws-csoc-operator-iam/terraform.tfstate` |
| `csoc-cluster-core/aws-csoc-cluster` | `csoc/aws-csoc-cluster/terraform.tfstate` |
| `csoc-cluster-core/aws-csoc-controller-iam` | `csoc/aws-csoc-controller-iam/terraform.tfstate` |
| `csoc-cluster-core/gitops-argocd-install` | `csoc/gitops-argocd-install/terraform.tfstate` |
| `spoke-fleet-update/aws-spoke-access-iam-<alias>` | `spokes/<alias>/aws-spoke-access-iam/terraform.tfstate` |
| `spoke-fleet-update/aws-csoc-to-spoke-access` | `csoc/aws-csoc-to-spoke-access/terraform.tfstate` |
| `spoke-fleet-update/gitops-argocd-bootstrap` | `csoc/gitops-argocd-bootstrap/terraform.tfstate` |

The stack files are the authority for these keys. Cross-stack consumers read
fixed S3 state keys; they never depend on generated directory locations.

## Configuration and prerequisites

Copy and populate `config/shared.auto.tfvars.json.example` as described in
[`config/README.md`](../../../config/README.md). The real file is ignored and may
contain account IDs and environment-specific paths; do not commit it.

The wrapper requires `terragrunt` and `jq`. Terraform, AWS CLI, valid AWS
credentials/profiles, backend bucket access, and suitable permissions are also
required by the generated units. Kubernetes/Helm units additionally require
network access to the EKS endpoint and `aws eks get-token` access.

## Operator flow

From the repository root:

```bash
bash scripts/terragrunt-stack.sh operators-iam plan
bash scripts/terragrunt-stack.sh csoc-cluster-core plan
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan
```

Review every unit plan and resolve unexpected replacements or destroys before
running the matching `apply`. When multiple spokes are enabled,
`TG_SPOKE_ALIAS` is mandatory for the spoke-fleet-update stack; operate each spoke IAM state
deliberately.

The wrapper writes dated logs, reports, and plan files below ignored `outputs/`.
Generated `.terragrunt-stack` trees may be regenerated and must not be edited.

See the stack-specific details:

- [`operators-iam`](operators-iam/README.md)
- [`csoc-cluster-core`](csoc-cluster-core/README.md)
- [`spoke-fleet-update`](spoke-fleet-update/README.md)
