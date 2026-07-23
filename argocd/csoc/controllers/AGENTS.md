# AGENTS.md

## Scope

Controller files are value layers for the `csoc-controllers` Helm chart. They
describe self-managed KRO, External Secrets, and ACK controller Applications;
they do not contain RGDs or per-spoke infrastructure instances.

## Values Contract

- `values.yaml` is the shared catalog and default configuration. Preserve the
  controller key as the stable ApplicationSet/Application name unless a
  deliberate migration is documented.
- `<cluster_type>-overrides/addons.yaml` is a narrow overlay. Use it to enable
  controllers and provide EKS- or Kind-specific settings; do not duplicate the
  full base catalog.
- Merge order is base values, cluster-type overlay, then an optional
  spoke/chart-specific values file. A key must retain a compatible type across
  all layers.
- Keep global selectors aligned with cluster Secret labels and management mode.
  EKS may use IRSA/pod identity while Kind uses injected credentials; do not
  copy the local credential model into EKS values.
- Controller repo/chart versions, namespaces, service accounts, value files,
  and pod identity settings must match what the generated ApplicationSet
  expects. Do not place credentials or account-specific ARNs in values.
- Adding or removing a controller requires checking the Terraform controller
  IAM policy/capability inputs, both cluster-type overlays, bootstrap selectors,
  operator reports, and documentation.

## Validation

Render both supported cluster types after shared template or base-value changes:

```bash
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/kind-overrides/addons.yaml
```

Inspect generated ApplicationSet names, selectors, namespaces, source charts,
value-file ordering, and sync waves—not merely whether Helm exits successfully.

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
