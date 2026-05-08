# CSOC Helm Charts

| Chart | Purpose |
|-------|---------|
| `csoc-controllers` | Generates one ApplicationSet per enabled controller value |
| `ack-multi-acct` | Creates ACK CARM namespaces and IAMRoleSelectors |
| `kro-aws-instances` | Renders per-spoke `infrastructure-values` ConfigMap and KRO instance CRs |

KRO RGDs live outside Helm under `argocd/csoc/kro` and are applied by the `csoc-kro` Application.
