# AGENTS.md

## Project Overview

gen3-kro is an EKS Cluster Management Platform. A CSOC control-plane cluster
uses Argo CD, KRO, and ACK controllers to reconcile Gen3 infrastructure across
AWS spoke accounts.

The current architecture plan lives in `plan/`. Treat those files as the source
of truth when implementing the separation of function:

- Terragrunt orchestrates environments and dependency ordering.
- Terraform implements reusable modules.
- AWS foundation modules must not use Kubernetes or Helm providers.
- In-cluster bootstrap modules target an existing named cluster.
- Argo CD, KRO, and ACK own post-bootstrap reconciliation.

## Instruction Precedence

Read the nearest `AGENTS.md` before editing a subtree. More specific AGENTS
files override this root file for their paths. `.github` instruction files are
compatibility shims for Copilot; do not treat them as more authoritative than
AGENTS.md or `plan/*.md`.

## Repository Map and Ownership

- `terragrunt/live/aws/` is the operator-facing environment layer. Its stack
  files select config, instantiate units, assign state keys, and define order.
- `terraform/catalog/units/` adapts a stack to one independently stateful
  Terraform root. `terraform/catalog/modules/` contains reusable resource
  implementations.
- `argocd/bootstrap/` is the first GitOps entry point. `argocd/csoc/` contains
  controller values, Helm charts, and plain KRO RGDs. `argocd/spokes/` contains
  per-spoke instance and workload values.
- `config/` contains tracked examples and documentation plus ignored local
  environment inputs. `iam/` contains tracked IAM policy source templates.
- `scripts/` contains explicit operator entry points and read-only reports.
  `.devcontainer/` and the root `Dockerfile` provide the toolchain only.
- `docs/` explains the implemented system to new and recurring operators.
  `plan/` records architectural intent, migration decisions, and acceptance
  criteria; keep it synchronized with implementation changes.
- `.github/` contains optional GitHub/Copilot compatibility assets. It does not
  override `AGENTS.md`.

## Tracked, Local, and Generated Material

- Add instruction files only to directories that contain tracked source or
  tracked examples. Do not add them to generated trees merely to make those
  trees appear documented.
- Tracked examples must remain usable templates with placeholders. Real
  `config/shared.auto.tfvars.json`, `config/ssm-repo-secrets/input.json`, PEM
  files, and local Kubernetes Secret manifests remain ignored.
- Treat `.terragrunt-stack/`, `.terraform/`, state, plans, dated `outputs/`,
  generated provider/backend/module files, credential reports, kubeconfigs,
  port-forward files, and rendered secret payloads as disposable local output.
  They may be inspected when diagnosing a run but must never be edited as the
  source of a repository change or committed.
- `references/`, `.git/`, `.vscode/`, `.outputs/`, `third-party-licenses/`, and
  every `**/.terragrunt-stack/` tree are outside instruction-maintenance scope.

## File and Documentation Requirements

- Keep exact names, paths, commands, state keys, sync waves, and ownership
  descriptions consistent across code and docs. Search all consumers before
  renaming a config key, output, bridge key, unit, chart value, or file.
- Write for both first-time users and regular operators: state what a component
  owns, what it consumes and produces, which context runs it, whether it
  mutates external state, and how success or failure is verified.
- Architecture descriptions must name each part by its actual role. Connectors
  must have a stated direction and meaning; do not use unattached arrows,
  ambiguous crossings, or a line that silently changes from containment to
  dependency semantics.
- Keep root `README.md` focused on system orientation and the supported command
  flow. Put contribution/testing policy in `CONTRIBUTING.md`, detailed runbooks
  in `docs/`, and subsystem contracts in the nearest subtree README.
- Keep tool versions aligned among `Dockerfile`, `.terraform-version`, tracked
  lock metadata, and documentation. Do not update a floating tool reference and
  describe it as reproducibly pinned.

## Safety Rules

Never commit secrets, real AWS account IDs, ARNs with account IDs, access keys,
session tokens, private keys, tfstate, tfplan files, generated `.terragrunt-stack`
content, `outputs/`, or local credential artifacts. Use placeholders in docs and
runtime injection for real values.

Do not run Terraform/Terragrunt apply or destroy commands unless the user
explicitly asks for execution. For this repo, infrastructure mutation must be
deliberate, reviewed, and environment-specific.

## Development Workflow

- Use `rg` for search.
- Keep edits scoped to the subsystem you are changing.
- Keep the implemented split-state ownership documented in `plan/` and do not
  reintroduce compatibility wrappers or combined Terraform roots.
- Keep generated artifacts out of tracked source.
- Use ASCII in new docs unless a file already requires non-ASCII.
- When a user adds a persistent repo requirement during a task, update the
  nearest relevant `AGENTS.md` file in the same change so the requirement is
  preserved.
- README architecture sections must use ASCII box-drawing diagrams (Unicode
  characters ┌─┐│└─┘→▼), not Mermaid. Use outer boxes for context boundaries,
  inner boxes for individual resources, and arrows for dependency direction.
- README architecture diagrams must draw explicit dependency chains and use
  separate boxes for units, modules, and concrete managed resources when those
  resources are known.

## Validation Commands

Run the narrowest applicable checks:

```bash
git diff --check
terraform fmt -check -recursive terraform/
terragrunt hcl format --check
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml
```

For AGENTS/instruction-only changes, `git diff --check` plus the explicit
search commands in the relevant plan are sufficient.

## Architecture Diagram Semantics

- Nesting means ownership or containment; it never means dependency.
- A solid connector between resource boxes means the destination consumes data,
  configuration, or a reference from the source. Draw fan-out and fan-in with
  explicit tee branches, keep arrowheads touching consumers, and leave resources
  unconnected when no such flow exists.
- Do not turn `depends_on`, Terragrunt ordering, Argo CD sync waves, an opaque
  ordering token, or observed apply sequence into a resource-data connector.
  Show ordering-only information with one detached guide such as `Deployment
  order only (not resource data): earlier -> later`, and arrange the diagram in
  that general direction.
- State connector meanings in a legend or adjacent text. Unit, module, or stack
  orchestration connectors may represent ordering when labeled; a connector
  must not silently switch between containment, data flow, and ordering.
