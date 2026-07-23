# AGENTS.md

## Scope

These are repository-owned Helm charts for generating Argo CD and KRO control
objects. RGDs remain plain YAML under `argocd/csoc/kro`; charts here instantiate
or deliver them but do not redefine their schemas.

## Shared Chart Rules

- Keep `Chart.yaml`, default `values.yaml` where present, templates, and README
  contracts synchronized. Increment the chart version for behavior or template
  changes that consumers must be able to identify.
- Templates must be deterministic from values. Do not use live-cluster lookup
  to hide an undeclared dependency. Use `required`/`fail` for mandatory inputs,
  quote string annotations, and preserve JSON strings until the chart explicitly
  decodes them.
- Never render plaintext credentials. Secret references, role ARNs, account
  IDs, and repository coordinates must come through documented runtime values.
- Keep Argo CD sync-wave annotations and KRO kind versions data driven where
  the values contract already supports them. A producer/consumer bridge order
  change must be reflected in values, templates, RGD docs, and spoke examples.

## Chart Responsibilities

- `csoc-controllers` emits one ApplicationSet per enabled controller key. Keep
  selectors, optional pod identity, multi-source value-file order, and app-name
  uniqueness consistent with controller values.
- `multi-account` decodes `clustersJson` to create namespaces, ACK CARM routing,
  and secret-writer service accounts. The bootstrap manifest passes JSON as an
  inline YAML string because Helm command-line setters misparse JSON braces;
  preserve that boundary.
- `kro-aws-instances` emits the `infrastructure-values` ConfigMap at wave `14`
  and enabled `AwsGen3*` instances at later waves. Instance kind suffixes must
  match installed RGD versions, and disabled instances must not render partial
  resources.

## Validation

- Run `helm lint` with representative values when defaults alone are
  insufficient, then run `helm template` with the exact consuming value stack.
- For controller chart changes, render both EKS and Kind overlays.
- For KRO instance changes, render `spoke1/infrastructure-values.yaml` and
  inspect kinds, namespaces, names, waves, ConfigMap keys, and absence of Secret
  values.
- For multi-account changes, provide a placeholder `clustersJson` value and
  inspect one rendered spoke; never use real account data in fixtures.

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
