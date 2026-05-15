# Spoke1 Gen3 Completion

Reviewed:
- `argocd/bootstrap`
- `argocd/spokes/spoke1/infrastructure-values.yaml`
- `argocd/spokes/spoke1/cluster-resources/cluster-values.yaml`
- `argocd/spokes/spoke1/spoke1dev.rds-pla.net/gen3-values.yaml`
- `argocd/csoc/kro/aws-rgds/gen3/v1`
- `references/gen3-build/helm/cluster-level-resources`
- `references/gen3-build/helm/gen3`

## Deployment Model

CSOC installs and owns the control plane flow:
- `csoc-controllers` installs CSOC controllers.
- `multi-account` installs per-spoke namespaces, ACK multi-account support, and secret-writer service accounts.
- `csoc-kro` installs KRO RGDs into the CSOC cluster.
- `fleet-instances` renders `kro-aws-instances`, which creates the KRO instances and bridge ConfigMaps in the CSOC-side `spoke1` namespace.

Those KRO instances then create AWS resources and Argo CD Applications:
- Infrastructure graphs create VPC, DNS, S3, Aurora, EKS, OpenSearch, IAM, and bridge ConfigMaps.
- `platform-helm1-rg.yaml` registers the spoke EKS cluster in CSOC Argo CD and creates the platform Application in CSOC Argo CD.
- The platform Application renders `cluster-level-resources`; its child Applications install workloads into the spoke cluster.
- `app-helm1-rg.yaml` creates the Gen3 Application in CSOC Argo CD, but the Gen3 workloads install into the spoke cluster namespace `gen3`.

This means the ordering is cross-cluster: CSOC must create AWS and register the spoke before the spoke add-ons can install, and External Secrets must be working in the spoke before Gen3 pods can read app secrets.

## Secret Model

AWS Secrets Manager should be the source of truth. The current Gen3 charts still consume Kubernetes `Secret` objects through `secretKeyRef` and mounted secret volumes, so "AWS stored/retrieved" means External Secrets Operator reads AWS Secrets Manager and projects runtime Kubernetes Secrets. Do not put secret material in Git or Helm values, and do not let Helm generate long-lived local secrets when an ExternalSecret path exists.

There are two separate SecretStore contexts:
- CSOC `spoke1`: `database1-rg.yaml` creates a SecretStore/ExternalSecret so ACK can read the Aurora master password while creating RDS. This is not the Gen3 app SecretStore.
- Spoke `gen3`: the Gen3 chart creates the app SecretStore and ExternalSecrets used by Gen3 pods. This depends on the `external-secrets` add-on being installed in the spoke cluster by `cluster-level-resources`.

## Blocking Next Steps

1. Enable the KRO instances for the deploy path. `infrastructure-values.yaml` currently sets every `instances.*.enabled` value to `false`, so no infrastructure instances, bridge ConfigMaps, platform Application, or Gen3 Application will be created from that file.

2. Verify External Secrets per cluster. Do not compare the CSOC database graph to the spoke platform chart; they run in different clusters. The real dependency is: CSOC External Secrets must serve `external-secrets.io/v1` for `database1-rg.yaml`, and spoke External Secrets must serve `v1beta1` plus `PushSecret v1alpha1` for Gen3. Current config appears aligned if `csoc-controllers` installs CSOC external-secrets chart `2.0.1` and `cluster-level-resources` installs spoke external-secrets chart `0.9.13`.

3. Remove `global.externalSecrets.clusterSecretStoreRef` from `gen3-values.yaml` unless you create a real `ClusterSecretStore` in the spoke cluster. The comment says Database1 creates it, but Database1 creates a namespaced CSOC SecretStore. With the current value, some Gen3 ExternalSecrets render against a missing spoke `ClusterSecretStore` and will not sync.

4. Match the spoke app SecretStore service account to IAM. `app-iam1-rg.yaml` trusts `system:serviceaccount:gen3:external-secrets-sa`, but `gen3-values.yaml` currently sets `global.aws.secretStoreServiceAccount.name: external-secrets`. If these differ, ESO in the spoke cannot assume the AWS role and every AWS-backed app secret read fails.

5. Keep Secrets Manager names inside the IAM scope, or broaden the scope intentionally. Current app secret names are built from `data.secretNames.*` as `<name>-<namespace>-<suffix>`, such as `gen3-spoke1-metadata-g3auto`, which stays inside the existing `gen3-*` policy scope.

6. If Gen3 should create AWS DB secrets, expand IAM from read-only to write. The Gen3 PushSecret flow needs `secretsmanager:CreateSecret`, `PutSecretValue`, `UpdateSecret`, `TagResource`, and usually `ListSecrets` in addition to `GetSecretValue` and `DescribeSecret`. The current `app-iam1-rg.yaml` external-secrets role only has read permissions, so PushSecret cannot create AWS secrets yet.

7. Turn off Helm-created app secrets where ExternalSecret support exists. Current values set `audit.externalSecrets.createK8sAuditSecret`, `fence.externalSecrets.createK8sFenceConfigSecret`, `fence.externalSecrets.createK8sJwtKeysSecret`, and `indexd.externalSecrets.createK8sServiceCredsSecret` to `true`. Set them to `false` and create the matching AWS Secrets Manager secrets instead.

8. Choose the DB secret creation mode. Gen3 can create service DB AWS secrets with `PushSecret`, but it creates a temporary `*-dbcreds-bootstrap` Kubernetes Secret as the source object. If that is acceptable, set `global.externalSecrets.pushSecret: true` or per-service `externalSecrets.pushSecret: true` and expand IAM as above. If no Kubernetes source secret is acceptable, add an AWS-side generator after `database-bridge` exists, such as an ACK Secrets Manager graph or external provisioning script, then let Gen3 consume those secrets through ESO.

9. Make the Aurora master secret usable by both layers. The CSOC database graph only needs property `password`, but Gen3 DB jobs read `username`, `password`, `host`, and `port` from `global.postgres.externalSecret`. If one AWS secret is used for both, populate or update all four keys after Aurora exposes its endpoint, and keep `data.secretNames.auroraMasterPassword` aligned with the database/app bridge.

10. Patch chart gaps that always create Kubernetes Secrets. `fence-creds` is generated by Helm and includes DB credentials; that does not match the AWS-source goal. Patch the Fence chart to support an ExternalSecret for `fence-creds`, or accept it as an explicit exception. `fence-secret`, `sheepdog-secret`, `peregrine-secret`, and `indexd-settings` are packaged config Secret objects; review them and patch if any environment-specific secret material is added.

11. Fix audit IRSA. `app-iam1-rg.yaml` trusts `system:serviceaccount:gen3:audit-sa`, while the chart defaults to `audit-service-sa`. If the service account name does not match, the audit pod receives the role annotation but cannot assume the role.

12. Patch platform S3 mountpoint IRSA. `platform-helm1-rg.yaml` passes the KRO-created S3 CSI role ARN, but `cluster-level-resources/templates/aws-s3-mountpoint.yaml` hardcodes `AmazonEKS_S3_CSI_DriverRole-{{ .Values.cluster }}`. The spoke S3 CSI driver will use the wrong role unless the chart honors the parameter or the role name is changed.

13. Gate app deployment on spoke add-ons. Gen3 ExternalSecrets depend on the spoke `external-secrets` controller and CRDs. Confirm `platform-helm` waits for the child `external-secrets` Application to be healthy before `app-helm` syncs, or add an explicit wait/gate.

14. Limit ExternalDNS. `cluster-values.yaml` leaves `external-dns.domainFilters` empty. Set it to `["rds-pla.net"]` so the spoke add-on only manages the intended hosted zone.

15. Resolve portal and manifest choices. `storage.manifestBucketName` and `storage.dashboardBucketName` are empty, and `app-helm1-rg.yaml` uses those to disable `manifestservice` and `portal`. If this commons needs the portal, add the dashboard bucket; if not, change `global.frontendRoot` away from `portal`.

16. Fix Fence usersync storage. `fence.usersync.userYamlS3Path` points at `s3://gen3-users/sepoke1-users/user.yaml`, but `app-iam1-rg.yaml` grants Fence access to the KRO usersync bucket. Point it at `s3://gen3-spoke1-usersync/...` or grant the role access to the external bucket.

## AWS Secrets Manager Inventory

Use the rendered `<name>-<namespace>-<suffix>` names if keeping the current IAM policy:

- `gen3-spoke1-aurora-master-password`: JSON with at least `username`, `password`, `host`, and `port`.
- `gen3-spoke1-arborist-creds`, `gen3-spoke1-audit-creds`, `gen3-spoke1-fence-creds`, `gen3-spoke1-indexd-creds`, `gen3-spoke1-metadata-creds`, `gen3-spoke1-peregrine-creds`, `gen3-spoke1-sheepdog-creds`, `gen3-spoke1-wts-creds`: service DB JSON with `database`, `username`, `password`, `host`, and `port`.
- `gen3-spoke1-audit-g3auto`: key `audit-service-config.yaml`.
- `gen3-spoke1-fence-config`: key or value for `fence-config.yaml`.
- `gen3-spoke1-fence-jwt-keys`: key `jwt_private_key.pem`.
- `gen3-spoke1-fence-google-app-creds-secret`: property `fence_google_app_creds_secret.json`.
- `gen3-spoke1-fence-google-storage-creds-secret`: property `fence_google_storage_creds_secret.json`.
- `gen3-spoke1-indexd-service-creds`: JSON with `fence`, `sheepdog`, `ssj`, and `gateway`.
- `gen3-spoke1-metadata-g3auto`: properties `base64Authz.txt`, `dbcreds.json`, and `metadata.env`.
- `gen3-spoke1-wts-g3auto`: property `appcreds.json`.
- `gen3-spoke1-wts-oidc-client`: JSON with `client_id` and `client_secret` if the WTS OIDC job is not used.
- Add later only if enabled: `gen3-spoke1-manifestservice-g3auto`, `gen3-spoke1-ssjdispatcher-creds`, Hatchery/Stata license, Slack webhook, Guppy/ETL/OpenSearch-specific secrets.

Suggested value changes:

```yaml
global:
  postgres:
    externalSecret: gen3-spoke1-aurora-master-password
  aws:
    secretStoreServiceAccount:
      name: external-secrets-sa
  externalSecrets:
    clusterSecretStoreRef: ""
    createLocalK8sSecret: false
    # Uncomment only if using Gen3 PushSecret to seed service DB creds in AWS.
    # pushSecret: true

audit:
  serviceAccount:
    name: audit-sa
  externalSecrets:
    createK8sAuditSecret: false
    auditG3auto: gen3-spoke1-audit-g3auto
    dbcreds: gen3-spoke1-audit-creds

fence:
  externalSecrets:
    createK8sFenceConfigSecret: false
    createK8sJwtKeysSecret: false
    createK8sGoogleAppSecrets: false
    dbcreds: gen3-spoke1-fence-creds
    fenceConfig: gen3-spoke1-fence-config
    fenceJwtKeys: gen3-spoke1-fence-jwt-keys
    fenceGoogleAppCredsSecret: gen3-spoke1-fence-google-app-creds-secret
    fenceGoogleStorageCredsSecret: gen3-spoke1-fence-google-storage-creds-secret

indexd:
  externalSecrets:
    createK8sServiceCredsSecret: false
    dbcreds: gen3-spoke1-indexd-creds
    serviceCreds: gen3-spoke1-indexd-service-creds

arborist: { externalSecrets: { dbcreds: gen3-spoke1-arborist-creds } }
metadata: { externalSecrets: { createK8sMetadataSecret: false, dbcreds: gen3-spoke1-metadata-creds, metadataG3auto: gen3-spoke1-metadata-g3auto } }
peregrine: { externalSecrets: { dbcreds: gen3-spoke1-peregrine-creds } }
sheepdog: { externalSecrets: { dbcreds: gen3-spoke1-sheepdog-creds } }
wts: { externalSecrets: { createK8sWtsSecret: false, createWtsOidcClientSecret: false, dbcreds: gen3-spoke1-wts-creds, wtsG3auto: gen3-spoke1-wts-g3auto, wtsOidcClient: gen3-spoke1-wts-oidc-client } }
```

## Graph Notes

- `compute1-rg.yaml` uses one private subnet for OpenSearch, which matches the current single-node, zone-awareness-off config. Before scaling OpenSearch above one AZ, add explicit values for zone awareness and derive the subnet list from that setting.
- Keep `kubernetesNetworkConfig.elasticLoadBalancing.enabled: true` for EKS Auto Mode.
- Keep `availabilityZones` out of the Aurora `DBCluster`; let the DB subnet group and instances control placement to avoid ACK churn.
- Keep the domain-security bridge split by condition so the bridge does not reference excluded WAF resources.
- Add `retry.limit: 5` to child Applications rendered by `cluster-level-resources` if retry limits are required uniformly; wrapper Applications already have retry limits.

## Validation

Render locally before syncing:

```bash
tmpdir="$(mktemp -d)"
cp -a references/gen3-build/helm "$tmpdir/helm"

helm template cluster-level-resources references/gen3-build/helm/cluster-level-resources \
  -f argocd/spokes/spoke1/cluster-resources/cluster-values.yaml

helm dependency build "$tmpdir/helm/gen3"
helm template gen3 "$tmpdir/helm/gen3" \
  -n gen3 \
  -f argocd/spokes/spoke1/spoke1dev.rds-pla.net/gen3-values.yaml
```

After sync, check CSOC first, then spoke:

```bash
kubectl get rgd | grep awsgen3
kubectl -n spoke1 get awsgen3compute1,awsgen3database1,awsgen3platformhelm1,awsgen3apphelm1
kubectl -n argocd get applications

kubectl --context <spoke-context> -n gen3 get secretstore,externalsecret
kubectl --context <spoke-context> -n gen3 describe externalsecret
kubectl --context <spoke-context> -n gen3 get jobs,pods
```
