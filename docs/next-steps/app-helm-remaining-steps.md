# App Helm Pending Steps

1. Decide the owner for each AWS-backed app secret: manual, KRO-seeded, or app/runtime-generated.
2. Enable the matching app secret RGD only for secrets KRO owns; otherwise seed the AWS secret manually or let the app/runtime path create it.
3. Add `bootstrapSecretName` and `secretWriterServiceAccountName` fields to app secret RGDs that still hardcode `gen3-secret-bootstrap` or `gen3-secret-writer-sa`.
4. Add embedded `created: "true"` markers to JSON payloads still missing them, especially `audit-g3auto` and `manifestservice-g3auto`; leave `fence-config.yaml` markerless unless the chart tolerates an extra field.
5. Decide the WTS OIDC path: add an AWS seed path for `gen3-spoke1-wts-oidc-client` or keep it app-created/local.
6. Resolve bucket override semantics: keep suffix-only behavior and document it, or support full bucket names without prefixing.
7. Validate the remaining AppHelm combinations in-cluster: minimal, manifestservice, dashboard, and opt-in secret RGDs.
