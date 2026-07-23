# AGENTS.md

## Scope

This subtree is the production Gen3 RGD graph. Phase directories organize the
current dependency tiers; they are not independent deployments.

## Phase and Bridge Contract

- `v1/Phase0` contains independent roots such as network security, domain
  security, messaging, and secret bootstrap. Each publishes its named bridge.
- `v1/Phase1` contains compute, database, and storage consumers of Phase 0
  network data and publishes compute/database/storage bridges.
- `v1/Phase2` contains spoke access, platform IAM, and application IAM. These
  consume compute/storage/database contracts as required and publish their own
  access/IAM bridges.
- `v1/Phase3` contains platform Helm registration and platform add-on delivery;
  it consumes compute, platform IAM, and spoke access and publishes
  `platform-helm-bridge`.
- `v1/Phase4` contains application Helm and secret-dependent delivery, consuming
  all relevant upstream non-secret metadata.

The table in `README.md` is the human-readable source for current producers and
consumers. Update it with any graph change.

## Production RGD Requirements

- Keep bridge ConfigMaps single-producer and namespace-local. Use kebab-case
  keys and identical feature-flag guards for optional producer data and the
  resources that consume it.
- Publish resource identifiers, endpoints, ports, names, and secret references
  only. For Aurora, publish the RDS-managed Secrets Manager ARN and deterministic
  target Secret name, never the password.
- Use exact least-privilege IAM resource relationships where status-derived ARNs
  are available. Any wildcard required for discovery or create-before-ARN must
  be documented and conditioned where AWS permits.
- Preserve encryption, public-access blocks, private subnet placement, and
  production deletion policy unless a reviewed architecture decision changes
  them.
- New kinds or versions require matching instance-chart support and a migration
  path; do not repurpose an existing numbered kind for an incompatible schema.

## Validation

- Parse all changed RGD YAML.
- Verify every changed bridge key with `rg` across this subtree and the instance
  chart.
- Check every changed ACK resource for region/adoption/deletion annotations and
  identity plus `ACK.ResourceSynced` readiness.
- Render the representative spoke chart and verify enabled kind versions and
  wave order. Do not create instances as part of source-only validation.

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
