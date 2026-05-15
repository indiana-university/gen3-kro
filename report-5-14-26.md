# Deployment Flow Investigation - 2026-05-14

Generated: 2026-05-15

Scope: current local worktree in `/workspaces/gen3-kro`. I inspected Terraform, ArgoCD bootstrap, the `kro-aws-instances` Helm chart, KRO RGDs, spoke1 values, and the local `references/gen3-build` source. I did not use live cluster access.

## Checks Run

- `helm lint argocd/csoc/helm/kro-aws-instances -f argocd/spokes/spoke1/infrastructure-values.yaml` passed.
- `helm template test argocd/csoc/helm/kro-aws-instances -f argocd/spokes/spoke1/infrastructure-values.yaml` passed.
- `helm lint argocd/csoc/helm/multi-account` passed.
- Raw YAML parse of the KRO RGD manifests under `argocd/csoc/kro/aws-rgds/gen3/v1` passed.
- A full local render of `references/gen3-build/helm/gen3` was not possible because the local reference checkout does not have the umbrella chart dependencies under `charts/`. I used direct template inspection for Gen3-build secret behavior.

## Current Deployment Flow

1. Terraform creates the CSOC cluster, ArgoCD, ACK/External Secrets support, the ArgoCD cluster secret, and the spoke account ACK role.
2. `argocd/bootstrap/csoc-controllers.yaml` installs CSOC controllers.
3. `argocd/bootstrap/multi-account.yaml` creates one CSOC Kubernetes namespace per spoke and annotates it for ACK CARM. It also creates one `gen3-secret-writer-sa` per spoke namespace. For spoke1, ACK resources in namespace `spoke1` reconcile against the spoke AWS account through `spoke1-spoke-role`, and secret writer Jobs use the service account to assume the same Terraform-created spoke role before touching Secrets Manager.
4. `argocd/bootstrap/csoc-kro.yaml` applies all KRO ResourceGraphDefinitions from `argocd/csoc/kro`.
5. `argocd/bootstrap/fleet-instances.yaml` renders `argocd/csoc/helm/kro-aws-instances` once per spoke. The spoke fleet cluster secret points at `https://kubernetes.default.svc`, so the KRO instances and their child Kubernetes resources run in the CSOC cluster namespace named after the spoke.
6. The `kro-aws-instances` chart creates `infrastructure-values` plus KRO CR instances. Those CRs create ACK resources, Jobs, bridge ConfigMaps, and later ArgoCD Applications for platform and app Helm.
7. `platform-helm1-rg.yaml` creates the spoke cluster registration/add-on Application.
8. `app-helm1-rg.yaml` creates the Gen3-build app Application that targets the registered spoke EKS cluster.

Rendered order for current spoke1 values:

| Wave | Rendered resources |
| --- | --- |
| 14 | `ConfigMap/infrastructure-values` |
| 15 | `AwsGen3NetworkSecurity1/gen3`, `AwsGen3DomainSecurity1/gen3`, `AwsGen3Messaging1/gen3` |
| 20 | `AwsGen3Storage1/gen3`, `AwsGen3Compute1/gen3` |
| 25 | `AwsGen3SpokeAccess1/gen3`, `AwsGen3PlatformIAM1/gen3`, `AwsGen3AppIAM1/gen3` |
| 26 | `AwsGen3SecretBootstrap1/gen3-secret-bootstrap` |
| 27 | `AwsGen3Database1/gen3` |
| 30 | `AwsGen3PlatformHelm1/gen3` |
| 35 | Optional app secret RGDs, currently disabled in spoke1, and `AwsGen3AppHelm1/gen3` |

## Secret Ownership

The DB cluster master credential is supposed to be created by KRO right now. `AwsGen3SecretBootstrap1` creates the ACK Secrets Manager metadata object and a Job writes the value. `AwsGen3Database1` waits for `aurora-master-password-secret-bridge.data.created == "true"` before creating the DB cluster. Gen3-build then consumes the AWS secret through `global.postgres.externalSecret`.

That is not a duplicate of the Gen3-build service DB credentials. With `global.externalSecrets.pushSecret: true`, Gen3-build creates temporary Kubernetes bootstrap secrets and PushSecrets for per-service DB credentials such as `gen3-spoke1-fence-creds`, `gen3-spoke1-indexd-creds`, `gen3-spoke1-wts-creds`, etc. It does not push the Aurora master credential.

Gen3-build also has a PushSecret path for Fence JWT keys, but only if there is a source Kubernetes Secret. Current spoke1 values set `fence.externalSecrets.createK8sJwtKeysSecret: false`, so AppHelm points the chart at the ConfigMap-derived AWS name, currently `gen3-spoke1-fence-jwt-keys`.

`wts-oidc-client` is not pushed to AWS by Gen3-build. Current values leave `wts.externalSecrets.createWtsOidcClientSecret` at the Gen3-build default of `true`, so WTS creates a local Kubernetes Secret instead of reading AWS. If that flag is changed to `false`, something else must create the AWS secret first.

## Findings

### Resolved: secret writer Jobs now authenticate through the spoke role

The secret writer Jobs run in the CSOC cluster because KRO child resources are created in the CSOC spoke namespace. The current worktree moves `gen3-secret-writer-sa` into the `multi-account` chart. Each service account is annotated with the CSOC source role, and each Job calls `sts assume-role` into the namespace's Terraform-created `<spoke>-spoke-role`.

A CSOC pod does not get a token from the spoke EKS OIDC provider, so secret bootstrap must not depend on a spoke-OIDC-trusted writer role.

Current watch item: keep this CSOC source role trust broad enough for `system:serviceaccount:*:gen3-secret-writer-sa`, and keep the spoke role policy broad enough for every bootstrap secret name.

### Resolved: AppIAM no longer emits optional empty-bucket policies

Current spoke1 storage leaves `manifestBucketName` and `dashboardBucketName` blank. `storage1-rg.yaml` correctly emits empty optional bucket fields in the bridge for those combinations.

`app-iam1-rg.yaml` now waits for non-empty/non-loading required storage and compute bridge values. It creates `manifestserviceRole` only when `storageBridge.data['manifest-bucket-arn']` is non-empty, and creates `dashboardRole` only when `storageBridge.data['dashboard-bucket-arn']` is non-empty. The app IAM bridge emits `""` for disabled optional role ARNs and real ARNs when those optional buckets are enabled.

`app-helm1-rg.yaml` waits for required AppIAM bridge role ARNs to be non-empty/non-loading and allows optional manifestservice/dashboard role ARNs to be empty.

### Resolved: AppHelm passes app data through but does not decide service enablement

The optional app secret RGDs now run at the same ArgoCD sync wave as AppHelm. They are opt-in companions, not hard prerequisites, because some secret values may need the app to be running before they can be generated.

`app-helm1-rg.yaml` still passes bridge-derived values such as bucket names, role ARNs, database connection settings, SQS URLs, and the app SecretStore role. It no longer sets `manifestservice.enabled` from whether a manifest bucket exists. The spoke `gen3-values.yaml` remains the control point for enabling or disabling app services.

`app-helm1-rg.yaml` now also pins the Gen3 ExternalSecret AWS secret-name values for Fence, Audit, Metadata, Indexd, Manifestservice, WTS, and service DB credentials. AppHelm and the secret RGDs both read suffixes from `infrastructure-values.data.secret-name-*` and build `<name>-<namespace>-<suffix>`, falling back to the hardcoded service suffix if the ConfigMap value is blank. The Fence SSH key name is pinned too, but the Gen3 chart consumes it only when dbGaP usersync is enabled.

### High: current spoke1 consumes app config secrets that are not created

spoke1 disables the app secret RGDs:

- `fenceConfigSecret.enabled: false`
- `fenceGoogleAppCredsSecret.enabled: false`
- `fenceGoogleStorageCredsSecret.enabled: false`
- `wtsG3AutoSecret.enabled: false`
- `auditG3AutoSecret.enabled: false`
- `metadataG3AutoSecret.enabled: false`
- `indexdServiceCredsSecret.enabled: false`
- `manifestserviceG3AutoSecret.enabled: false`

But the Gen3 app values are configured to consume several of these through ExternalSecrets:

- Fence config, JWT keys, and Google app/storage secrets are not locally created.
- Audit `gen3-spoke1-audit-g3auto` is not locally created.
- Indexd `gen3-spoke1-indexd-service-creds` is not locally created.
- Metadata defaults to ExternalSecret mode in Gen3-build.
- WTS `gen3-spoke1-wts-g3auto` defaults to ExternalSecret mode.
- Manifestservice is currently disabled, but if enabled it defaults to ExternalSecret mode.

This is valid only if those AWS Secrets Manager values are created manually, by an enabled app secret RGD, or by an app/runtime bootstrap flow.

### High: app secret RGDs still hardcode bootstrap Secret and writer ServiceAccount names

The app secret RGDs do not expose `bootstrapSecretName` or `secretWriterServiceAccountName` in their schema. They hardcode:

- `secretName: gen3-secret-bootstrap`
- ServiceAccount `gen3-secret-writer-sa`

`audit-g3auto` and `manifestservice-g3auto` do not mount the bootstrap secret. The Aurora master password bootstrap is separate and generates its own password; it does expose `secretWriterServiceAccountName`.

Fix direction: make the bootstrap Secret name configurable in the RGD schema and chart values, with safe defaults.

### High: not every AWS secret value gets a `created` field

The requested pattern was that each AWS secret value include a `created` field. Current implementation is mixed:

- Aurora, WTS, Google app creds, Google storage creds, metadata, and indexd write JSON with `created: "true"`.
- `fence-config` writes raw YAML and has no embedded `created` field.
- `audit-g3auto` writes JSON but no embedded `created` field.
- `manifestservice-g3auto` writes JSON but no embedded `created` field.

The bridge ConfigMap reports `created` from Job success, not by reading the AWS secret value. That can mark a pre-existing or malformed secret as created.

### Resolved: app External Secrets IAM scope covers the current app secret prefixes

`app-iam1-rg.yaml` allows the app External Secrets role to read/write:

- `${schema.spec.name}-*`
- `fence-*`
- `indexd-*`
- `audit-*`
- `metadata-*`
- `manifestservice-*`
- `wts-*`

That covers the current `gen3-spoke1-*` names produced from `data.secretNames`. AppHelm now passes those names explicitly to the Gen3 chart, rather than relying on implicit chart defaults.

### Medium: bucket name defaults and override semantics are confusing

The chart ConfigMap renders blank bucket values for storage defaults. `storage1-rg.yaml` then generates actual bucket names for compulsory buckets:

- `gen3-spoke1-logging`
- `gen3-spoke1-data`
- `gen3-spoke1-upload`
- `gen3-spoke1-usersync`

This works, but the ConfigMap itself still shows blank values. Also, if an operator supplies a full bucket name in values, the RGD prepends `global.name` and namespace again. For example, setting `dataBucketName: gen3-spoke1-data` would render `gen3-spoke1-gen3-spoke1-data`.

Fix direction: decide whether values are suffixes or full bucket names. For your stated convention, a suffix model is fine, but comments and defaults should say that clearly. If full names are allowed, do not prepend when an override is supplied.

### Medium: Gen3-build default service set differs from current spoke1 values

Gen3-build defaults enable several services, including `etl`, `hatchery`, and `manifestservice`. Current spoke1 values disable those three. AppHelm now passes the manifest bucket and role ARN through when available but does not force `manifestservice.enabled`.

That is okay if intentional, but it means the spoke1 minimum deployment is not the upstream Gen3-build default service set. If manifestservice should be enabled, set a manifest bucket suffix and enable the service in spoke values.

### Medium: `metadataName` is not the current clash

The Helm helper supports `metadataName` only as an override for the KRO CR `metadata.name`. No current values set it, so every rendered KRO CR is named `gen3` under a different Kind. Kubernetes allows the same name across different resource kinds in the same namespace.

It is unnecessary for the current single-instance-per-kind flow, but it is the only escape hatch for multiple CRs of the same Kind. If removed, replace it with a deterministic default per kind rather than deleting the capability blindly.

### Medium: OAuth JavaScript origin mismatch

The deployment hostname is `spoke1dev.rds-pla.net`, and the local OAuth client JSON under `argocd/spokes/spoke1` has:

- JavaScript origin: `https://spoke1dev.rds-pla.net`
- Redirect URI: `https://spoke1dev.rds-pla.net/user/login/google/login/`

The screenshot with `https://dev.planx-pla.net` as the JavaScript origin is wrong for this deployment unless that host is also serving the app. The redirect URI in the screenshot is correct. Do not commit the local OAuth client JSON with real credentials.

## Practical Answers

DB cluster credentials: KRO is intended to create the Aurora master secret. Gen3-build consumes it. There is no intended duplication with per-service DB credentials.

Deleting the Kubernetes ACK `Secret` CR for the Aurora master secret: with the current `secretBootstrap.spec.deletionPolicy: retain`, deleting the `secretsmanager.services.k8s.aws/v1alpha1` `Secret` object removes the Kubernetes control-plane object but leaves the AWS Secrets Manager secret active. The rendered ACK object carries `services.k8s.aws/deletion-policy: retain`, and the AWS secret name remains `gen3-spoke1-aurora-master-password` for spoke1. If the KRO instance is still present, KRO/ArgoCD may recreate the ACK CR as the desired Kubernetes object.

Application linkage after that delete: the Gen3 app is linked by AWS secret name, not by the ACK CR object. `app-helm1-rg.yaml` passes `global.postgres.externalSecret` from `databaseBridge.data['aurora-master-password-sm-name']`, and Gen3-build renders an `ExternalSecret` with target name/key matching that AWS secret name. So the app remains linked as long as the AWS secret remains, the `ExternalSecret`/`SecretStore` remain, and the app external-secrets role can read the secret.

Deleting the ESO-created in-cluster Kubernetes `Secret` target is different: AWS Secrets Manager is not deleted, and External Secrets should recreate the Kubernetes `Secret` on its next refresh while the `ExternalSecret` still exists. There can be a short app disruption if pods need the target Secret before it is recreated.

Per-service DB credentials: Gen3-build PushSecret creates those when `global.externalSecrets.pushSecret: true` and the app DB init path runs. After the AWS secrets exist, you can turn off PushSecret and keep ExternalSecrets enabled so the app reads from AWS. Do not disable ExternalSecrets unless you are returning to local Kubernetes secrets.

App config secrets: if `createK8s*` is `false`, Gen3-build expects AWS Secrets Manager to already contain the value. Those are valid RGD/manual-bootstrap candidates. If `createK8s*` is `true`, the app chart creates the Kubernetes Secret locally and that secret should not also be owned by an RGD.

WTS OIDC: not pushed to AWS by the current Gen3-build PushSecret flow. Current values leave it as a local app-created Kubernetes Secret. If you want AWS-backed WTS OIDC, add an explicit AWS seed path for `gen3-spoke1-wts-oidc-client` and set `createWtsOidcClientSecret: false`.

## Recommended Fix Order

1. Decide for each app config secret whether it is manual, KRO-seeded, or app/runtime-generated.
2. Keep `data.secretNames.*` suffixes aligned with the secrets each app secret RGD owns.
3. Make app secret RGDs configurable for bootstrap Secret and writer ServiceAccount names.
4. Add embedded `created` fields where the AWS secret value format allows it.
5. Decide suffix-vs-full-name semantics for buckets and update defaults/comments accordingly.
6. Validate the AppHelm flow against enabled service combinations.
