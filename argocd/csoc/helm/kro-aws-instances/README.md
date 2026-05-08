# kro-aws-instances

Helm chart for per-spoke KRO instance delivery. The `fleet-instances` ApplicationSet renders this chart once per spoke using `argocd/spokes/<spoke>/infrastucture-values.yaml`.

It creates:

| Resource | Wave | Purpose |
|----------|------|---------|
| `ConfigMap/infrastructure-values` | 14 | Flat values consumed by RGDs via `externalRef` |
| `AwsGen3*` instances | 15-35 | KRO CRs that expand into ACK-managed AWS resources |

RGD schemas live in `argocd/csoc/kro/aws-rgds`; this chart only creates instances of those schemas.
