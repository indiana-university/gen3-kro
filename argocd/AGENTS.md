# AGENTS.md

## Scope

Argo CD owns post-bootstrap reconciliation: controller applications, KRO RGDs,
multi-account wiring, and per-spoke KRO instances. Terraform may install Argo
CD and seed the first bootstrap ApplicationSet; continuous resources stay here.

## Directory Ownership

- `bootstrap/` contains raw ApplicationSet entry points selected by labels and
  annotations on Argo CD cluster Secrets.
- `csoc/controllers/` contains shared controller values and EKS/Kind override
  layers consumed by the `csoc-controllers` chart.
- `csoc/helm/` contains the charts that generate controller ApplicationSets,
  multi-account resources, and per-spoke KRO instances.
- `csoc/kro/` contains plain YAML ResourceGraphDefinitions and capability tests.
  Do not Helm-template RGD source files.
- `spokes/<spoke>/` contains tracked per-spoke infrastructure and workload
  values. Use the exact filename `infrastructure-values.yaml`.

## Reconciliation Contract

- Preserve the ownership chain: bootstrap ApplicationSet -> bootstrap
  Application -> controller/RGD/multi-account/fleet ApplicationSets -> KRO
  instances -> ACK and Kubernetes resources.
- Keep sync waves consistent with actual prerequisites: KRO controller before
  RGDs, ACK controllers before ACK-backed instances, multi-account namespace
  wiring before spoke instances, and bridge producers before consumers.
- ApplicationSet cluster-generator selectors and template references are an API
  with Terraform's Argo CD cluster Secrets. Search both `argocd/` and
  `terraform/catalog/modules/gitops-argocd-bootstrap/` before changing labels or
  annotations such as `fleet_member`, `cluster_type`, `enable_*`, or repository
  coordinates.
- Keep repository URL, revision, and base-path data driven by cluster Secret
  annotations. Do not hardcode an operator's fork or branch into shared
  manifests.
- Review `preserveResourcesOnDeletion`, automated pruning, server-side apply,
  retry, and ignore-difference settings as lifecycle policy—not formatting.

## Documentation

- README tables must describe what each file renders, which controller or chart
  consumes it, sync ordering, and whether deletion is retained or pruned.
- Use exact resource names, chart names, paths, bridge names, and file names.
  Explain connector direction in architecture diagrams and distinguish GitOps
  containment from runtime dependency.
- If a value or selector changes, update the producing Terraform contract, the
  consuming ApplicationSet/chart, representative spoke values, and nearby
  documentation together.

## Validation

```bash
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/kind-overrides/addons.yaml
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml
```

Parse changed YAML and run the narrowest chart render that exercises it. A
render is validation only; do not apply it unless explicitly requested.

## Security

Do not commit Kubernetes Secrets with real values, real account IDs,
account-bearing ARNs, generated outputs, state, plans, `.terragrunt-stack`
content, kubeconfigs, or local credentials. Ignored local Secret manifests may
exist under a spoke; do not use or copy them into tracked documentation.

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
