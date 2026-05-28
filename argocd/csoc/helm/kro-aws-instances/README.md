# kro-aws-instances

Helm chart for per-spoke KRO instance delivery. The `fleet-instances` ApplicationSet renders this chart once per spoke using `argocd/spokes/<spoke>/infrastucture-values.yaml`.

It creates:

| Resource | Wave | Purpose |
|----------|------|---------|
| `ConfigMap/infrastructure-values` | 14 | Flat values consumed by RGDs via `externalRef` |
| `AwsGen3*` instances | 15-35 | KRO CRs that expand into ACK-managed AWS resources |

RGD schemas live in `argocd/csoc/kro/aws-rgds`; this chart only creates instances of those schemas.

## Database Secret Flow

`AwsGen3Database1` publishes only non-secret database metadata plus the
RDS-managed Secrets Manager secret ARN in `database-bridge`. `AwsGen3AppHelm1`
passes that ARN to Gen3 Build as `global.postgres.externalSecretRemoteKey` and
passes the deterministic spoke Kubernetes target Secret name as
`global.postgres.externalSecret`.

The password is not embedded in this chart, CSOC KRO bridges, or ArgoCD
parameters. External Secrets Operator in the spoke reads the RDS-managed AWS
secret directly and creates the Kubernetes Secret that Gen3 currently consumes.
