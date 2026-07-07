# Migration Roadmap

## Implementation Status

As of this rollout, Phase 1 and Phase 2 source changes are implemented in the
repo:

- `terraform/catalog/modules/aws-csoc-foundation` contains the AWS-only CSOC
  foundation boundary and has no Kubernetes or Helm provider.
- `terraform/catalog/modules/csoc-in-cluster-bootstrap` targets an existing named
  cluster for Argo CD install and bootstrap resources.
- `terraform/catalog/modules/csoc-cluster` remains as the compatibility wrapper
  and includes `moved` blocks for the module split.
- `terragrunt/live/aws/csoc/terragrunt.stack.hcl` adds the Terragrunt-first CSOC
  stack with developer identity, foundation, spoke IAM, and bootstrap units.
- `terraform/catalog/modules/aws-spoke` can now consume an exact CSOC source role
  ARN while retaining compatibility fallback trust.
- Devcontainer post-create no longer auto-applies infrastructure.
- `terragrunt/live/aws/prereq-iam` provides a developer-identity-only
  prerequisite IAM path that can be applied without creating the CSOC cluster or
  spoke resources.
- `scripts/state-migration.sh` contains the guarded state-only migration helper;
  it requires explicit confirmation and does not run `terraform apply`.

Phase 3 state migration has not been executed. Do not remove the compatibility
wrapper, deprecated `iam-setup` stack, or state-migration phase until plans have
been run with AWS credentials and state has been moved deliberately.

## Phase 0: Baseline and Safety

Tasks:

- Run and archive current `terraform plan`, Terragrunt IAM plan, and Helm render
  output for `csoc-controllers` and `kro-aws-instances`.
- Confirm no tracked secrets and no accidental local secret files staged.
- Document current state addresses before moving resources.
- Add CI or at least local validation scripts for `terraform fmt`,
  `terragrunt hcl format`, Helm template rendering, and YAML parsing.

Acceptance criteria:

- Current deployment path remains unchanged.
- Baseline plans are available for comparison.
- Existing local secret files remain unread and uncommitted.

Rollback:

- No infrastructure changes in this phase.

## Phase 1: Split Terraform Modules Without Changing Behavior

Tasks:

- Create `terraform/catalog/modules/aws-csoc-foundation` by extracting AWS-only
  resources from `aws-csoc`.
- Create `terraform/catalog/modules/csoc-in-cluster-bootstrap` from the Argo CD
  namespace/service account/Helm resources and the current `argocd-bootstrap`
  resources.
- Keep the existing `csoc-cluster` composite module temporarily as a compatibility
  wrapper calling both new modules.
- Remove Kubernetes and Helm providers from the foundation module.
- Make the in-cluster module work against a pre-named cluster.

Acceptance criteria:

- Existing `scripts/install.sh plan` still produces equivalent infrastructure
  behavior through the compatibility wrapper.
- Foundation module has no Kubernetes, Helm, or local providers.
- In-cluster module can be planned with only cluster connection inputs and GitOps
  metadata.

Rollback:

- Repoint the compatibility wrapper to the current `aws-csoc` and
  `argocd-bootstrap` modules.

## Phase 2: Add Terragrunt CSOC Stack

Tasks:

- Add `terragrunt/live/aws/csoc/terragrunt.stack.hcl`.
- Add units for `developer_identity`, `csoc_foundation`, `spoke_iam`, and
  `csoc_in_cluster_bootstrap`.
- Use Terragrunt dependency outputs so `spoke_iam` receives the exact CSOC source
  role ARN from `csoc_foundation`.
- Keep `terragrunt/live/aws/iam-setup` as a deprecated compatibility stack until
  state is migrated.
- Add a wrapper script such as `scripts/csoc-stack.sh` for common Terragrunt
  actions.

Acceptance criteria:

- Terragrunt can plan the full CSOC environment in dependency order.
- Spoke IAM can be planned after foundation without needing wildcard role-name
  trust.
- Plain Terraform root remains available during transition but is no longer the
  preferred entry point.

Rollback:

- Use the existing `terraform/env/aws/csoc-cluster` and
  `terragrunt/live/aws/iam-setup` paths.

## Phase 3: State Migration

Tasks:

- Prepare `moved` blocks or `terraform state mv` commands for resources split
  out of the current composite state.
- Move AWS foundation resources to `csoc/foundation/terraform.tfstate`.
- Move in-cluster resources to `csoc/in-cluster-bootstrap/terraform.tfstate`.
- Move or retain IAM state according to the final stack layout.
- Add state locking before collaborative use.

Acceptance criteria:

- New Terragrunt stack plans cleanly with no unintended destroys.
- Resource addresses are documented.
- Destroy order is documented and tested in a non-production environment.

Rollback:

- Restore previous backend state versions and old entrypoints if a state move
  produces unexpected replacement plans.

## Phase 4: Tighten IAM and Operator Workflow

Tasks:

- Change spoke trust from CSOC account root plus wildcard `ArnLike` to exact role
  ARN where migration permits.
- Decide whether the devcontainer role remains trusted by spoke roles for manual
  cleanup. If yes, scope and document that exception.
- Replace Terraform `local_file` operator artifacts with scripts that read
  Terraform outputs.
- Change devcontainer lifecycle from `setup init apply connect` to `setup` or
  `setup connect`.
- Extract shared credential/config helpers from `container-init.sh` and
  `kind-csoc.sh`.
- Rename `scripts/ssm-repo-secrets` if desired, since it writes AWS Secrets
  Manager secrets rather than SSM Parameter Store values.

Acceptance criteria:

- Opening the devcontainer does not mutate infrastructure.
- IAM trust policies are tighter or explicitly documented with temporary
  exceptions.
- Credential validation behavior is shared between EKS and Kind workflows.

Rollback:

- Restore old trust policy input and devcontainer command while preserving the
  module split.

## Phase 5: Documentation and Cleanup

Tasks:

- Update `README.md`, `docs/architecture.md`, `docs/deployment-guide.md`, and
  `.devcontainer/README.md` to describe the Terragrunt-first flow.
- Standardize all references to `infrastructure-values.yaml`.
- Remove or ignore generated `.terragrunt-stack` artifacts and cached Python
  bytecode from source paths.
- Add a small architecture decision record for each major boundary:
  Terragrunt orchestration, in-cluster bootstrap module, GitOps ownership, and
  IAM trust model.

Acceptance criteria:

- New contributors can deploy by following only the updated docs.
- Old two-phase host Terragrunt plus container Terraform language is gone or
  clearly marked deprecated.
- Validation passes in CI or documented local checks.

Rollback:

- Documentation-only changes can be reverted independently.

## Suggested Final Command Flow

```bash
# Host
bash scripts/mfa-session.sh <MFA_CODE>

# Host or devcontainer with mounted credentials
cd terragrunt/live/aws/csoc
terragrunt stack run plan
terragrunt stack run apply

# Optional connect after bootstrap
bash scripts/container-init.sh setup connect
```

## Key Non-Goals

- Do not rewrite KRO RGDs into Terraform.
- Do not replace Argo CD with Terraform-managed continuous resources.
- Do not make the devcontainer mandatory for local Kind RGD authoring.
- Do not combine generated outputs, state, or local secrets into tracked source.
