# kro-aws-instances

Helm chart for per-spoke KRO instance delivery. The `fleet-instances` ApplicationSet renders this chart once per spoke using `argocd/spokes/<spoke>/infrastucture-values.yaml`.

It creates:

| Resource | Wave | Purpose |
|----------|------|---------|
| `ConfigMap/infrastructure-values` | 14 | Flat values consumed by RGDs via `externalRef` |
| `AwsGen3*` instances | 15-35 | KRO CRs that expand into ACK-managed AWS resources |

RGD schemas live in `argocd/csoc/kro/aws-rgds`; this chart only creates instances of those schemas.

## Database Secret Mirror

The chart exposes `data.databaseSecretMirror` and
`instances.databaseSecretMirror` for the optional AWS-side Aurora password
mirror:

```yaml
data:
  databaseSecretMirror:
    enabled: "true"
    scheduleExpression: "rate(5 minutes)"

instances:
  databaseSecretMirror:
    enabled: true
```

Only non-secret values go in this chart. The RDS password is read by Lambda from
the RDS-managed Secrets Manager secret and written to the deterministic mirror
secret that Gen3 Build already references with `global.postgres.externalSecret`.
Do not set ACK `Secret.spec.secretString` for this flow. The Lambda zip is a
non-secret S3 artifact in the spoke logging bucket, initial creation is handled
by a one-shot Lambda invoke Job, and EventBridge keeps the mirror fresh afterward.
