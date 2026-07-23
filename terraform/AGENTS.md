# AGENTS.md

## Scope

Terraform is the module implementation layer. Terragrunt owns environment
orchestration.

## Module Boundaries

- AWS foundation modules create AWS resources only: VPC, EKS, OIDC, IAM roles,
  optional EKS capabilities, and outputs for downstream units.
- AWS foundation modules must not configure Kubernetes or Helm providers.
- In-cluster bootstrap modules may use Kubernetes and Helm providers, but they
  must target an existing named cluster.
- Do not move Argo CD-managed controllers, RGDs, or KRO instances into
  Terraform. Terraform seeds the control loop only.
- Keep cluster, controller IAM, spoke access, and in-cluster ownership separate.

## Canonical Boundary Names

- Keep an exact one-to-one name between each catalog unit and wrapped root
  module: `gitops-argocd-bootstrap`, `gitops-argocd-install`,
  `aws-csoc-cluster`, `aws-csoc-controller-iam`,
  `aws-csoc-to-spoke-access`, `aws-csoc-operator-iam`, and
  `aws-spoke-access-iam`.
- Do not add aliases or compatibility wrapper roots for retired boundary names.

## State and Providers

- Keep state split by Terragrunt unit.
- Do not commit tfstate, plans, `.terraform/`, or generated backend files.
- Prefer provider lockfiles and CI validation for reproducibility.
- Use explicit outputs for dependency handoff rather than re-parsing names in
  downstream modules.

## Documentation

- When a user adds a persistent Terraform or unit documentation requirement,
  record it in this file or a nearer `AGENTS.md` in the same change.
- Module and unit README architecture sections must use ASCII box-drawing
  diagrams (Unicode characters ┌─┐│└─┘→▼), not Mermaid.
- Module README architecture diagrams must end at concrete managed resources or
  generated resource groups. Unit README architecture diagrams must end at
  modules: show the unit, its wrapped module, dependent units and their wrapped
  modules, and any child-module dependency chain, but no resources.
- A unit is a containment boundary. Draw its wrapped root module inside the unit
  box, never as a separate box connected from the unit by an arrow. Draw child
  modules inside their parent root module; use arrows only for actual data or
  reference flow between module boxes.
- Architecture diagrams must not show variables, outputs, data sources,
  providers, backends, state paths, or literal Terraform resource addresses.
  In module diagrams, use human-readable resource labels, keep resources as the
  smallest nodes, and depict repeated resources as a containing group with two
  examples followed by an ellipsis. In unit diagrams, keep modules as the
  smallest nodes.
- Draw dependency paths horizontally from left to right with `→`. Stack
  parallel, sibling, and repeated resources vertically; do not place resources
  at the same dependency level beside one another.
- Divide diagrams into explicit left-to-right dependency stages. Label each
  column `Stage N - <role>` with a spaced ASCII hyphen between the stage number
  and role. Reuse a stage number for parallel objects at the same dependency
  depth, and do not draw a stage boundary through a dependency connector.
- Stage labels describe diagram layout only. They are not resources,
  containment, dependency connectors, or authorization to infer deployment
  order where the implementation exposes only resource-data flow.
- Draw each horizontal dependency as a continuous connector from the source
  box to the destination box, with the `→` arrowhead touching the destination
  border. Connect through vertical sides or junctions (`│`, `├`, `┤`), never
  box corners, and do not leave whitespace between connectors and objects.
- A left-to-right path may fan out through a horizontal tee bus using `┬`, `┼`,
  and `┐`, with `│` and `▼` drops to explicit branch objects. These drops are
  allowed even though the primary dependency direction remains horizontal.
- Do not consolidate independent paths into aggregate dependency nodes such as
  `Dependencies`, `VPC-dependent resources`, or `role-dependent resources`.
  Draw every dependency path explicitly from left to right. Draw a shared
  resource once and fan its individual connectors in or out through its side.
- Title Terraform context boxes only as `Module: <name>` or `Unit: <name>`.
  Express dependency status through placement and arrows, not prefixes such as
  `Dependency module:` or `Deployment-order dependency module:`.

## Security

Never commit secrets, real account IDs, ARNs with account IDs, tfstate,
generated `.terragrunt-stack` content, `outputs/`, or local credential
artifacts.

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
