# AGENTS.md

## Scope

This tree contains KRO ResourceGraphDefinitions and capability tests. The
`csoc-kro` Argo CD Application recursively syncs these files as plain YAML;
never Helm-template RGD source files.

## RGD Structure

- Use `apiVersion: kro.run/v1alpha1`, `kind: ResourceGraphDefinition`, and a
  versioned kind following `AwsGen3<Component><Version>`. Metadata names are
  lowercase without hyphens; filenames are lowercase and end in `-rg.yaml`.
- Keep schema fields typed with the KRO schema DSL (for example,
  `string | required=true`). New optional fields need safe defaults so existing
  instances remain valid.
- A breaking schema change—removing or renaming fields or changing incompatible
  types—requires a new versioned kind. Do not force-delete CRDs or strip
  finalizers as part of a source edit.
- Keep each composed resource name unique and stable. Use `includeWhen` for
  conditional resources; do not construct conditional entries inside an array
  when separate resources are the proven capability pattern.

## ACK and Dependency Rules

- Every ACK resource template must include the intended region,
  `services.k8s.aws/adoption-policy`, and
  `services.k8s.aws/deletion-policy` annotations.
- ACK `readyWhen` must check both a stable resource identity/status field and an
  `ACK.ResourceSynced == True` condition. Handle status propagation with KRO
  optional chaining and `.orValue()` so absent status does not break evaluation.
- Share cross-RGD values through one documented bridge ConfigMap producer and
  `externalRef` consumers. Bridge keys are kebab-case, non-secret, and stable.
  Never publish passwords, tokens, private keys, or secret payloads in a bridge.
- Keep Argo CD instance waves in the `kro-aws-instances` chart. RGDs may share a
  delivery wave because runtime dependency belongs to instances and bridge
  readiness.
- Retain/deletion behavior is an infrastructure lifecycle decision. Do not
  change it solely to make tests or teardown faster.

## Change Coordination

- A schema field, kind version, bridge name/key, feature flag, or status output
  change may affect its RGD, all consuming RGDs, chart defaults/templates,
  spoke `infrastructure-values.yaml`, reports, and docs. Search all of them.
- Keep `aws-rgds/gen3/README.md` as the readable graph contract and
  `aws-rgds/test/README.md` as the capability/risk index.
- Use precise descriptors for resource roles and connector direction. A bridge
  arrow means producer data consumed by `externalRef`, not resource ownership.

## Validation

- Parse every changed YAML file and inspect the full RGD, not only the edited
  expression.
- Render `argocd/csoc/helm/kro-aws-instances` with a representative spoke when
  schema or kind/version inputs change.
- Search changed ACK resources for annotations and dual readiness checks, and
  search bridge keys across all producers and consumers.
- Cluster-side dry-run, Argo CD sync, test-instance creation, and deletion can
  contact or mutate real AWS through ACK. Do not run them unless explicitly
  requested and the target context is confirmed.

## Safety

Do not commit secrets, real account IDs, account-bearing ARNs, generated output,
state, plans, `.terragrunt-stack` content, kubeconfigs, or local credentials.

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
