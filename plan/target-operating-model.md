# Target Operating Model

## Ownership model

The catalog enforces an exact one-to-one boundary: a unit named `X` wraps only
the root module named `X`. The canonical names are:

```text
aws-csoc-operator-iam
aws-csoc-cluster
aws-csoc-controller-iam
gitops-argocd-install
aws-spoke-access-iam
aws-csoc-to-spoke-access
gitops-argocd-bootstrap
```

Terragrunt retains the three operator-facing stacks:

```text
operators-iam
└── aws-csoc-operator-iam

csoc-cluster-core
├── aws-csoc-cluster
├── aws-csoc-controller-iam
└── gitops-argocd-install

spoke-fleet-update
├── aws-spoke-access-iam-<alias>  # generated instance of the canonical unit
├── aws-csoc-to-spoke-access
└── gitops-argocd-bootstrap
```

The `spoke-fleet-update` wrapper accepts `aws-spoke-access-iam` and resolves the selected
alias to `aws-spoke-access-iam-<alias>`.

## Dependency and data flow

1. `aws-csoc-operator-iam` exports role maps, per-user role maps, MFA metadata,
   EKS access-entry data, and the exact subset of roles approved for spokes.
2. `aws-csoc-cluster` consumes operator EKS entries and exports cluster/OIDC
   metadata.
3. `aws-csoc-controller-iam` consumes cluster metadata and exports functional
   controller role ARNs.
4. `gitops-argocd-install` consumes cluster and Argo CD controller identity.
5. Each `aws-spoke-access-iam` consumes the ACK controller ARN and approved
   operator role ARNs.
6. `aws-csoc-to-spoke-access` consumes ACK controller and spoke role ARNs.
7. `gitops-argocd-bootstrap` consumes cluster, controller, install, spoke, and
   cross-account readiness outputs.

Mocks may construct deterministic values for non-apply commands only. Normal
handoff uses outputs rather than reconstructed names.

## Physical names

- Cluster and VPC: `<csoc_alias>-csoc-cluster`,
  `<csoc_alias>-csoc-vpc`.
- Controller roles: `<csoc_alias>-ack-controller-role`,
  `<csoc_alias>-argocd-controller-role`,
  `<csoc_alias>-kro-controller-role`, and
  `<csoc_alias>-external-secrets-role`.
- Spoke roles: `<spoke_alias>-<role_key>-access-role`.
- CSOC spoke policy: `<csoc_alias>-ack-assume-spoke-roles`.
- Operator roles: `<csoc_alias>-csoc-operator-<role_key>`.
- Bootstrap chart, release, and ApplicationSet:
  `gitops-argocd-bootstrap`.

Protocol-facing Argo CD names remain stable: namespace/release `argocd`,
standard service accounts, repository secrets, and cluster secrets.

## Operator IAM contract

Users are keyed by stable aliases and always refer to existing IAM users.
Roles are keyed by function and specify enabled state, assigned users, exact
external principals, MFA, session duration, permission JSON, EKS access policy,
and spoke eligibility.

An enabled role must have at least one exact principal. User keys, physical
names, session duration, and JSON policies are validated. Each user has one
aggregate `sts:AssumeRole` policy. Terraform may manage virtual MFA devices but
never IAM users.

The default role is `infrastructure-admin`. Session tooling selects a role with
`--role-key`, reads non-secret structured outputs, and writes no profile files
unless the explicit profile-generation command is run.

## Deployment order

After operator migration, first deployment is:

1. `aws-csoc-cluster`
2. `aws-csoc-controller-iam`
3. `gitops-argocd-install`
4. one `aws-spoke-access-iam-<alias>` per spoke
5. `aws-csoc-to-spoke-access`
6. `gitops-argocd-bootstrap`

Argo CD, KRO, and ACK own post-bootstrap reconciliation.
