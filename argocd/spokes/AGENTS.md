# AGENTS.md

## Scope

Each child directory is a tracked GitOps values overlay for one spoke. It
selects KRO instances and supplies values referenced by the Applications those
instances create. It is not a place for live Kubernetes Secrets.

## Per-Spoke Contract

- Keep `infrastructure-values.yaml` as the exact root filename consumed by the
  `fleet-instances` ApplicationSet and `kro-aws-instances` chart.
- Keep `global`, flattened `data`, and `instances` values compatible with chart
  defaults and the installed RGD schemas. Instance names, versions, namespaces,
  feature flags, and sync waves must preserve bridge producer-before-consumer
  order.
- `cluster-resources/cluster-values.yaml` is the platform add-on values source
  referenced by `AwsGen3PlatformHelm1`. Hostname directories such as
  `<hostname>/gen3-values.yaml` are application values sources referenced by
  `AwsGen3AppHelm1`. Keep configured repo paths and filenames exact.
- A spoke alias must agree with environment config, selected Terragrunt fleet
  input, Argo CD cluster-generator name, namespace, IAM policy lookup, and any
  path derived from that alias.
- Use placeholder-only example Secret manifests. A local `secrets.yaml`, real
  endpoint, account ID, role ARN, password, private key, or token is ignored
  material and must never be tracked or copied into documentation.
- When adding a spoke, update the local config, IAM policy source when the
  default is insufficient, values tree, and operator documentation as one
  reviewed onboarding change.

## Validation

```bash
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml
```

For a different spoke, substitute its tracked values file. Inspect the rendered
ConfigMap and every enabled instance kind/wave. Parse cluster/application values
with `yq`, but do not apply them or read ignored local Secret files merely to
validate tracked documentation.

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
