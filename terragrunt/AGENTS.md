# AGENTS.md

## Scope

Terragrunt is the environment orchestration layer for CSOC infrastructure and
IAM.

## Rules

- Model dependency order explicitly across `operators-iam`,
  `csoc-cluster-core`, and `spoke-fleet-update`.
- Pass role ARNs and cluster metadata through Terragrunt dependency outputs.
- Keep unit state keys stable and documented.
- Do not commit generated `.terragrunt-stack` content, generated Terraform
  files, tfstate, tfplan files, outputs, secrets, real account IDs, or ARNs with
  account IDs, or local credential artifacts.
- Use fixed S3 state keys for cross-stack contracts; never reference another
  stack's generated directory.
- Keep stack unit labels, catalog source names, generated paths, and state-key
  suffixes aligned with the seven canonical boundaries:
  `gitops-argocd-bootstrap`, `gitops-argocd-install`,
  `aws-csoc-cluster`, `aws-csoc-controller-iam`,
  `aws-csoc-to-spoke-access`, `aws-csoc-operator-iam`, and
  `aws-spoke-access-iam`.
- The per-spoke generated path is `aws-spoke-access-iam-<alias>`; the wrapper
  command remains the canonical `aws-spoke-access-iam`.

## Documentation

- When a user adds a persistent Terragrunt or stack documentation requirement,
  record it in this file or a nearer `AGENTS.md` in the same change.
- Stack README architecture sections must use ASCII box-drawing diagrams
  (Unicode characters ┌─┐│└─┘→▼), not Mermaid.
- Stack README architecture diagrams must end at units: show the stack, the
  units it deploys, and dependent stacks or units when they exist, but no
  modules or resources.
- Architecture diagrams must not show variables, outputs, data sources,
  providers, backends, state paths, or literal Terraform resource addresses.
  Keep units as the smallest nodes in stack diagrams.
- Draw dependency paths horizontally from left to right with `→`. Stack
  parallel, sibling, and repeated resources vertically; do not place resources
  at the same dependency level beside one another.
- Divide diagrams into explicit left-to-right orchestration stages. Label each
  column `Stage N - <role>` with a spaced ASCII hyphen between the stage number
  and role. Reuse a stage number for parallel stacks or units at the same
  dependency depth, and do not draw a stage boundary through a connector.
- Stage labels describe diagram layout only. They are not stacks, units,
  containment, or dependency connectors; the adjacent legend must still state
  whether connectors mean ordering or data flow.
- Draw each horizontal dependency as a continuous connector from the source
  box to the destination box, with the `→` arrowhead touching the destination
  border. Connect through vertical sides or junctions (`│`, `├`, `┤`), never
  box corners, and do not leave whitespace between connectors and objects.
- A left-to-right path may fan out through a horizontal tee bus using `┬`, `┼`,
  and `┐`, with `│` and `▼` drops to explicit branch objects. These drops are
  allowed even though the primary dependency direction remains horizontal.
- Do not consolidate independent paths into an aggregate `Dependencies` node.
  Draw every stack and unit dependency path explicitly from left to right. Draw
  a shared object once and fan its individual connectors in or out through its
  side.
- Title context boxes only as `Stack: <name>` or `Unit: <name>`. Express
  dependency status through placement and arrows, not prefixes such as
  `Dependency stack:` or `Dependency unit:`.

## Preferred Operator Flow

```bash
bash scripts/terragrunt-stack.sh operators-iam plan
bash scripts/terragrunt-stack.sh csoc-cluster-core plan
TG_SPOKE_ALIAS=<alias> bash scripts/terragrunt-stack.sh spoke-fleet-update plan
```

Do not add workflow guidance that bypasses review of plans before apply.

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
