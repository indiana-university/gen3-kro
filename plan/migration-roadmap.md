# Migration Roadmap

## Completed

- Renamed the stacks to `operators-iam`, `csoc-cluster-core`, and
  `spoke-fleet-update`.
- Established the seven one-to-one unit/module boundaries and canonical state
  keys.
- Confirmed from the live backend that operator IAM was the only populated
  historical state.
- Copied operator state to
  `prereq/aws-csoc-operator-iam/terraform.tfstate` with S3 versioning enabled.
  The destination has identical resource/output content and an independent
  destination lineage.
- Moved the registered MFA device to its canonical Terraform address without
  changing its physical device name or tags.
- Created the canonical `infrastructure-admin` role and permission policy.
- Removed legacy configuration projection, compatibility resources, historical
  `moved` declarations, and migration-only scripts from source.

## Live IAM completion gate

The current legacy assumed-role session does not have `iam:PutUserPolicy`.
Consequently, the aggregate user policy
`allow-assume-csoc-operator-roles` was not created during the parallel apply.
The retired role, its inline policy, and its user assume policy remain live to
avoid operator lockout.

The latest live plan is `1 to add, 1 to change, 3 to destroy`: it creates the
missing aggregate user policy, adds the canonical `Stack = operators-iam` tag
to `infrastructure-admin`, and deletes the three retired IAM objects. The MFA
device is a no-op.

An authorized IAM-user or administrator session must:

1. Review the `operators-iam/aws-csoc-operator-iam` plan.
2. Confirm it creates the missing aggregate user policy, updates only canonical
   ownership tags, and deletes exactly the three retired IAM objects.
3. Apply the reviewed plan.
4. Obtain a fresh MFA session for `infrastructure-admin`.
5. Verify caller identity, backend access, and plans for all three renamed
   stacks.

The external IAM user and registered MFA device must remain unchanged.

## First deployment of the remaining boundaries

After the IAM completion gate:

1. `aws-csoc-cluster`
2. `aws-csoc-controller-iam`
3. `gitops-argocd-install`
4. one `aws-spoke-access-iam-<alias>` per spoke
5. `aws-csoc-to-spoke-access`
6. `gitops-argocd-bootstrap`

The cluster creates explicit EKS access entries for enabled operator roles and
keeps cluster-creator administration disabled. Spokes trust only controller
and approved operator ARNs received through state outputs.

## Acceptance gates

- All stack, unit, module, path, tag, command, and diagram names are canonical.
- The registered MFA device has the same physical name and tags as before.
- The retired role, policy, and user policy are absent after authorized cleanup.
- The canonical role is assumable through a fresh MFA session.
- Terraform tests, formatting, stack generation, and Helm rendering pass.
- After cluster creation, EKS entries and `kubectl auth can-i` confirm the
  intended operator boundaries.
