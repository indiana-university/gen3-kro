# AGENTS.md

## Scope

This directory contains focused KRO capability-test RGDs. Syncing an RGD creates
its CRD only; creating a test instance may create Kubernetes objects or real AWS
resources through ACK.

## Test Requirements

- Keep tests numbered and narrowly focused on one capability or known pattern.
  Do not rewrite an earlier test so its documented result changes; add the next
  numbered test when preserving evidence matters.
- Name files `krotestNN-<feature>-rg.yaml`, use a matching versioned test kind,
  and document the capability, expected result, dependencies, and whether an
  instance contacts AWS in `README.md`.
- Tests that exercise ACK must follow the same annotations, readiness, region,
  IAM, and lifecycle safety rules as production RGDs. Use placeholder inputs and
  restrictive policies.
- Cross-RGD producer/consumer tests must state their creation order and bridge
  contract. Conditional-resource tests should encode the proven `includeWhen`
  and fallback patterns without leaking them into unrelated production changes.
- Test instance manifests belong in an explicitly documented tracked overlay or
  as placeholder examples. Do not add auto-created instances to the recursively
  synced RGD directory.

## Validation and Safety

- YAML parsing and source inspection are always appropriate.
- Applying an instance, forcing sync, or deleting a test can mutate real AWS for
  ACK-backed tests. Require explicit user authorization, confirm the Kubernetes
  context/account/region, and document retained-resource cleanup before acting.
- Never use real account IDs, ARNs, credentials, secret values, or production
  names in test fixtures.

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
