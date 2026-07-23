# CSOC core stack

This stack creates the CSOC control-plane foundation in three ordered units:

1. `aws-csoc-cluster` consumes enabled operator-role access entries from
   `aws-csoc-operator-iam`, then creates the AWS VPC, subnets, NAT, EKS cluster,
   and OIDC provider.
2. `aws-csoc-controller-iam` consumes cluster outputs and creates controller IAM,
   optional EKS capabilities/access, and optional External Secrets pod identity.
3. `gitops-argocd-install` consumes cluster and IAM outputs, connects Kubernetes/Helm
   providers to that cluster, creates the Argo CD namespace, and optionally
   installs self-managed Argo CD.

The corresponding modules are documented in the
[`Terraform module catalog`](../../../../terraform/catalog/modules/README.md).
State remains split across `csoc/aws-csoc-cluster`,
`csoc/aws-csoc-controller-iam`, and `csoc/gitops-argocd-install`; see the
parent [state table](../README.md#state-ownership).

## Architecture

```text
Stage 1 - stack entrypoint   Stage 2 - cluster unit   Stage 3 - controller IAM unit   Stage 4 - Argo CD install unit
Orchestration order: earlier ──────────────────────→ later

┌──────────────────┐   ┌────────────────────┐   ┌───────────────────────────┐   ┌──────────────────────┐
│ Stack: csoc-cluster-core ├──→┤ Unit: aws-csoc-cluster ├──→┤ Unit: aws-csoc-controller-iam ├──→┤ Unit: gitops-argocd-install │
└──────────────────┘   └────────────────────┘   └───────────────────────────┘   └──────────────────────┘
```

## Mode selection

Controller `*_management_type` values select `self_managed` or `aws_managed`.
The matching enable flag must also be true before a role/capability is created.
Argo CD namespace creation is enabled when a self-managed install, an
AWS-managed capability, or GitOps bootstrap needs it. Core does not create repo
secrets, fleet secrets, or the bootstrap ApplicationSet; those belong to the
spoke-fleet-update stack.

## Runbook

```bash
bash scripts/terragrunt-stack.sh csoc-cluster-core plan
# Review all three unit plans before applying.
bash scripts/terragrunt-stack.sh csoc-cluster-core apply
```

For diagnosis or staged rollout, a generated unit can be planned by its path:

```bash
bash scripts/terragrunt-stack.sh csoc-cluster-core plan aws-csoc-cluster
bash scripts/terragrunt-stack.sh csoc-cluster-core plan aws-csoc-controller-iam
bash scripts/terragrunt-stack.sh csoc-cluster-core plan gitops-argocd-install
```

Unit-level mocks permit planning before dependencies exist, but an apply
requires real dependency outputs. The stack disables cluster-creator
administration and uses explicit enabled operator access entries. A public EKS
endpoint, NAT topology, Auto Mode, and controller capability settings still
carry security or cost implications and should be explicitly reviewed.

Remove fleet/GitOps dependencies before planning core destruction. AWS-managed
capabilities use a retain deletion policy, so verify residual AWS resources
instead of assuming core teardown removes them.
