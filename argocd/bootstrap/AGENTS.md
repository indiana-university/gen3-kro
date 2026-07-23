# AGENTS.md

## Scope

This directory is the first GitOps layer read by the Terraform-seeded bootstrap
ApplicationSet. Files here are raw Argo CD ApplicationSet manifests, not Helm
values and not rendered output.

## Manifest Requirements

- Keep one clearly named responsibility per file: controller ApplicationSets,
  recursive CSOC RGDs, multi-account wiring, or per-spoke instances.
- Use `goTemplate: true` with `missingkey=error`. Template values must come from
  documented cluster Secret labels/annotations so missing contracts fail
  visibly instead of silently selecting defaults.
- Cluster-generator selectors must be minimal and must match labels produced by
  `terraform/catalog/modules/gitops-argocd-bootstrap`. Coordinate both sides of
  any label or annotation rename.
- Keep add-ons and fleet repository coordinates separate. `$values` references,
  chart paths, and per-spoke paths must include the correct configured base
  path and exact `infrastructure-values.yaml` spelling.
- Preserve ordering and lifecycle intentionally. Current roles are controller
  generation at wave `-20`, multi-account wiring at `5`, RGD delivery at `10`,
  and fleet instances at `30`. Explain any wave change against a concrete
  dependency.
- Set automated prune/self-heal, `preserveResourcesOnDeletion`, server-side
  apply, and ignore differences according to ownership. Fleet infrastructure
  retention is not interchangeable with bootstrap cleanup.
- Do not embed account IDs, role ARNs, credentials, or a developer-specific
  repository URL. Multi-account inputs come from cluster Secret annotations.

## Documentation and Validation

- Update `README.md` when a file is added, removed, renamed, or changes what it
  creates.
- Parse each changed manifest with `yq`; inspect rendered Go-template strings as
  strings rather than trying to resolve them locally.
- Render the downstream chart or directory that the ApplicationSet references.
  Do not `kubectl apply` or force an Argo CD sync for documentation validation.

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
