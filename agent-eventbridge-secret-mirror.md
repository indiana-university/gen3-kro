# Agent Task: Add EventBridge/Lambda Aurora Secret Mirror

## Local Workspace Context

You are working in:

- Primary repo: `/workspaces/gen3-kro`
- Gen3 Build reference repo: `/workspaces/gen3-kro/references/gen3-build`
- Current KRO RGDs: `/workspaces/gen3-kro/argocd/csoc/kro/aws-rgds/gen3/v1`
- CSOC controller chart values: `/workspaces/gen3-kro/argocd/csoc/controllers`
- Per-spoke infrastructure values: `/workspaces/gen3-kro/argocd/spokes`

Treat `references/gen3-build` as local reference source. Prefer local repository evidence over web search, except to verify current ACK chart versions and CRD fields from official ACK/AWS sources.

## Goal

Implement an AWS-side compatibility mirror for the Aurora master credential so Gen3 Build can keep using:

```yaml
global:
  postgres:
    externalSecret: gen3-<spoke>-aurora-master-password
```

without putting the RDS master password into CSOC Kubernetes, KRO bridges, ArgoCD parameters, or ACK `Secret.spec.secretString`.

The intended flow is:

```text
RDS-managed master secret
        |
        | EventBridge schedule/change event
        v
Lambda sync function in the spoke AWS account
        |
        v
AWS Secrets Manager mirror secret
  gen3-<namespace>-aurora-master-password
        |
        v
Gen3 Build ExternalSecret in the spoke EKS cluster
        |
        v
Kubernetes Secret consumed by Gen3 DB setup jobs
```

The mirror secret must contain the keys Gen3 Build reads from the Kubernetes Secret:

```json
{
  "username": "postgres",
  "password": "<from RDS-managed secret>",
  "host": "<Aurora writer endpoint>",
  "port": "5432"
}
```

## Current Repo Findings

- `argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/database1-rg.yaml` already creates Aurora with `manageMasterUserPassword: true`.
- `database1-rg.yaml` publishes both:
  - `aurora-master-password-sm-name`: deterministic Gen3 mirror name, for example `gen3-spoke1-aurora-master-password`
  - `aurora-master-password-sm-arn`: actual RDS-managed Secrets Manager ARN
- `argocd/csoc/kro/aws-rgds/gen3/v1/Phase4/app-helm1-rg.yaml` currently passes only `aurora-master-password-sm-name` to `global.postgres.externalSecret`.
- `references/gen3-build/helm/gen3/templates/postgres-master-external-secret.yaml` uses `global.postgres.externalSecret` as both the Kubernetes Secret target name and the AWS Secrets Manager remote key.
- `references/gen3-build/helm/common/templates/_db_setup_job.tpl` expects the resulting Kubernetes Secret to contain `username`, `password`, `host`, and `port`.
- `argocd/csoc/controllers/values.yaml` already defines `ack-lambda` but does not define `ack-eventbridge`.
- `argocd/csoc/controllers/eks-overrides/addons.yaml` enables `ack-lambda`; `argocd/csoc/controllers/kind-overrides/addons.yaml` currently disables `ack-lambda`.
- `iam/_default/ack/inline-policy.json` already has Secrets Manager access for `rds!*` and `gen3-*`, but it does not currently grant EventBridge or Lambda management permissions.

## Design Rules

- Do not put any secret value in Git.
- Do not use ACK `secretsmanager.services.k8s.aws/Secret.spec.secretString` for the RDS password or mirror password.
- Do not create a KRO Job or CSOC pod that calls `secretsmanager:GetSecretValue` for the RDS master secret.
- Do not echo, log, annotate, label, or bridge the secret value.
- Non-secret values are fine in KRO bridges: secret names, ARNs, function ARNs, rule ARNs, endpoints, ports, and readiness markers.
- It is acceptable that Gen3 Build later creates a Kubernetes Secret in the spoke EKS cluster, because the current chart consumes DB values through `secretKeyRef`.
- The AWS-side mirror must be idempotent and safe to run repeatedly.

## Required Deliverables

### 1. Add ACK EventBridge Controller

Update `argocd/csoc/controllers/values.yaml` with an `ack-eventbridge` entry following the existing ACK controller pattern.

Use these chart facts, but verify them before finalizing:

```yaml
ack-eventbridge:
  enabled: false
  namespace: ack
  chartName: eventbridge-chart
  chartRepository: "public.ecr.aws/aws-controllers-k8s"
  defaultVersion: "1.2.3"
  annotationsAppSet:
    argocd.argoproj.io/sync-wave: "1"
  selectorMatchLabels:
    fleet_member: control-plane
    ack_management_mode: self_managed
  valuesObject:
    serviceAccount:
      annotations: {}
      create: true
      name: "ack-eventbridge-controller"
    aws:
      region: '{{.metadata.annotations.aws_region}}'
    enableCARM: false
    featureGates:
      IAMRoleSelector: "true"
```

Update `argocd/csoc/controllers/eks-overrides/addons.yaml` to enable `ack-eventbridge` with the same IRSA annotation pattern used by the other ACK controllers.

For `argocd/csoc/controllers/kind-overrides/addons.yaml`, either:

- enable both `ack-lambda` and `ack-eventbridge` if local Kind is expected to test this end-to-end against real AWS, or
- add `ack-eventbridge` disabled with the same `ignoreDifferences` block and document that the mirror RGD cannot reconcile in Kind until Lambda/EventBridge controllers are enabled.

### 2. Update ACK Spoke IAM Policy

Update `iam/_default/ack/inline-policy.json`. Keep policy scope compatible with the repo's existing naming conventions.

Add EventBridge discovery and management permissions needed by the ACK EventBridge `Rule` resource:

```json
[
  "events:DescribeRule",
  "events:ListRules",
  "events:ListTargetsByRule",
  "events:ListTagsForResource",
  "events:PutRule",
  "events:DeleteRule",
  "events:PutTargets",
  "events:RemoveTargets",
  "events:EnableRule",
  "events:DisableRule",
  "events:TagResource",
  "events:UntagResource"
]
```

Add Lambda discovery and management permissions needed by ACK Lambda `Function` resources and Lambda invoke permissions:

```json
[
  "lambda:CreateFunction",
  "lambda:DeleteFunction",
  "lambda:GetFunction",
  "lambda:GetFunctionConfiguration",
  "lambda:UpdateFunctionCode",
  "lambda:UpdateFunctionConfiguration",
  "lambda:TagResource",
  "lambda:UntagResource",
  "lambda:ListTags",
  "lambda:AddPermission",
  "lambda:RemovePermission",
  "lambda:GetPolicy"
]
```

Keep Lambda function names under a `gen3-*` or `<spoke>-*` naming convention so IAM resource scoping can stay narrow.

The existing `ManageIAMRolesForEKSResources` statement only allows role ARNs ending in `*-role` or `*-access`. Name the Lambda execution role accordingly, for example:

```text
gen3-<namespace>-aurora-secret-mirror-role
```

### 3. Add Database Secret Mirror RGD

Add a new RGD, probably:

```text
argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/database-secret-mirror1-rg.yaml
```

Suggested kind:

```yaml
kind: AwsGen3DatabaseSecretMirror1
```

Suggested schema fields:

```yaml
spec:
  name: string | required=true
  namespace: string | required=true
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="retain"
  infrastructureConfigMapName: string | default="infrastructure-values"
  networkSecurityBridgeName: string | default="network-security-bridge"
  databaseBridgeName: string | default="database-bridge"
  databaseSecretMirrorBridgeName: string | default="database-secret-mirror-bridge"
```

The RGD should externalRef:

- spoke `Namespace`
- `infrastructure-values`
- `network-security-bridge`
- `database-bridge`

The RGD should create:

- ACK Secrets Manager `Secret` metadata object for the mirror secret name, with no `secretString`
- ACK IAM `Role` for Lambda execution
- ACK Lambda `Function`
- ACK EventBridge scheduled `Rule` with the Lambda as a target
- optional ACK EventBridge change-event `Rule` with the Lambda as a target
- a non-secret bridge ConfigMap reporting names/ARNs/status only

Do not require the Lambda to be in the VPC. It only needs AWS API calls to RDS and Secrets Manager; it does not need to connect to Postgres.

### 4. Lambda Sync Logic

Add the Lambda source as plain text, for example under:

```text
argocd/csoc/kro/aws-rgds/gen3/lambda/rds-master-secret-mirror.py
```

Do not log secret values.

The handler should:

1. Read environment variables:
   - `DB_CLUSTER_IDENTIFIER`
   - `MIRROR_SECRET_NAME`
   - `AWS_REGION`
   - optional `MIRROR_SECRET_KMS_KEY_ID`
2. Call `rds.describe_db_clusters(DBClusterIdentifier=...)`.
3. Exit cleanly if:
   - the DB cluster is not available
   - `MasterUserSecret.SecretArn` is missing
   - `MasterUserSecret.SecretStatus` is not active
   - the writer endpoint is missing
4. Call `secretsmanager.get_secret_value(SecretId=<RDS managed secret ARN>)`.
5. Build the mirror JSON with:
   - `username`: prefer RDS secret JSON `username`, else DB cluster `MasterUsername`
   - `password`: from RDS secret JSON `password`
   - `host`: DB cluster writer endpoint
   - `port`: DB cluster port as a string
6. Create the mirror secret if it does not exist, otherwise put a new secret value.
7. Tag the mirror secret with non-secret metadata:
   - `ManagedBy=Gen3KRO`
   - `gen3.io/secret-purpose=aurora-master-password-mirror`
   - `gen3.io/source-secret-arn=<RDS managed secret ARN>`
   - `gen3.io/mirror-ready=true`

The function should be idempotent and safe for EventBridge to invoke every few minutes.

### 5. Lambda Code Packaging

Pick one packaging path and document it.

Preferred low-surprise options:

- Use ACK Lambda `Function.spec.code.s3Bucket` / `s3Key`, with a small script or CI step that zips and uploads the Lambda source to a non-secret artifact bucket.
- Or use ACK Lambda `Function.spec.code.zipFile` only if the repo has a clean generation workflow and the base64 zip is not manually edited.

Do not add a binary zip without documenting how it is regenerated.

If you use an S3 artifact:

- add config keys to `kro-aws-instances` values for `lambdaCodeS3Bucket`, `lambdaCodeS3Key`, and optional `lambdaCodeS3ObjectVersion`
- ensure the ACK/Lambda creation role can read that S3 object

### 6. EventBridge Rules

Create a scheduled rule. This is the initial creation bootstrap path and the rotation repair path.

Recommended default:

```text
rate(5 minutes)
```

Optionally add a change-event rule for quicker reaction to Secrets Manager changes. Keep the scheduled rule regardless, because EventBridge/CloudTrail change events are not a complete readiness mechanism.

The EventBridge `Rule` CRD supports `spec.targets`, so the Lambda target can be part of the Rule resource.

Important: Lambda targets still need a Lambda resource policy permission for EventBridge invocation. ACK Lambda's current CRDs include `Function`, `Alias`, `EventSourceMapping`, `FunctionURLConfig`, `LayerVersion`, `Version`, and `CodeSigningConfig`, but not a standalone `Permission` resource. Implement `lambda:AddPermission` with one of these non-secret approaches:

- a small one-shot AWS CLI Job that only grants EventBridge permission to invoke the function and does not read any secret values, or
- Terraform-managed `aws_lambda_permission`, if this repo's ownership model prefers Terraform for that permission.

The permission should scope `sourceArn` to the specific EventBridge rule ARN.

### 7. Update kro-aws-instances Chart

Update:

- `argocd/csoc/helm/kro-aws-instances/values.yaml`
- `argocd/csoc/helm/kro-aws-instances/templates/configmap.yaml`
- `argocd/csoc/helm/kro-aws-instances/templates/instances.yaml`

Add a new values block, default disabled unless all required code artifact values are present:

```yaml
data:
  databaseSecretMirror:
    enabled: "false"
    scheduleExpression: "rate(5 minutes)"
    eventPatternEnabled: "false"
    lambdaRuntime: "python3.13"
    lambdaHandler: "rds_master_secret_mirror.handler"
    lambdaTimeout: "60"
    lambdaMemorySize: "128"
    lambdaCodeS3Bucket: ""
    lambdaCodeS3Key: ""
    lambdaCodeS3ObjectVersion: ""

instances:
  databaseSecretMirror:
    enabled: false
    version: "1"
    syncWave: "28"
    spec:
      adoptionPolicy: "adopt-or-create"
      deletionPolicy: "retain"
      infrastructureConfigMapName: "infrastructure-values"
      networkSecurityBridgeName: "network-security-bridge"
      databaseBridgeName: "database-bridge"
      databaseSecretMirrorBridgeName: "database-secret-mirror-bridge"
```

The new instance should run after `database` and before `appHelm`.

### 8. Wire AppHelm Readiness Without Passing Secrets

Update `argocd/csoc/kro/aws-rgds/gen3/v1/Phase4/app-helm1-rg.yaml` only enough to wait on non-secret mirror readiness.

Suggested approach:

- add schema field `databaseSecretMirrorBridgeName: string | default="database-secret-mirror-bridge"`
- add externalRef for the mirror bridge
- wait for the bridge to report the mirror secret name and Lambda/EventBridge resources as synced
- keep passing `global.postgres.externalSecret` as `databaseBridge.data['aurora-master-password-sm-name']`

Do not pass `aurora-master-password-sm-arn` into Gen3 Build in this mirror approach.

If the mirror is disabled, preserve backward compatibility. Options:

- use separate includeWhen variants of AppHelm with and without the mirror bridge, or
- keep the mirror RGD enabled by default once the code artifact path exists.

Avoid making AppHelm read the mirror secret value. A non-secret bridge is enough; External Secrets and Gen3 pods can retry until the mirror value exists.

### 9. Update Spoke Values

Update `argocd/spokes/spoke1/infrastructure-values.yaml` only with non-secret configuration:

```yaml
data:
  databaseSecretMirror:
    enabled: "true"
    scheduleExpression: "rate(5 minutes)"
    lambdaCodeS3Bucket: "<artifact-bucket-name>"
    lambdaCodeS3Key: "<artifact-key>"

instances:
  databaseSecretMirror:
    enabled: true
```

Do not put a password or RDS secret JSON in this file.

### 10. Documentation

Update:

- `argocd/csoc/kro/aws-rgds/gen3/README.md`
- `argocd/csoc/helm/kro-aws-instances/README.md`
- `argocd/spokes/spoke1/README.md`

Document the secret flow and the exposure boundary:

- RDS password is not stored in CSOC Kubernetes.
- RDS password is not stored in ACK `Secret.spec.secretString`.
- Lambda sees the secret in memory during sync.
- The mirror secret exists in AWS Secrets Manager.
- Gen3 Build still materializes the mirror into a Kubernetes Secret inside the spoke EKS cluster because the chart uses `secretKeyRef`.

## Verification

Run at minimum:

```bash
git diff --check
helm template csoc-controllers argocd/csoc/helm/csoc-controllers \
  -f argocd/csoc/controllers/values.yaml \
  -f argocd/csoc/controllers/eks-overrides/addons.yaml >/tmp/csoc-controllers.yaml
helm template kro-aws-instances argocd/csoc/helm/kro-aws-instances \
  -f argocd/spokes/spoke1/infrastructure-values.yaml >/tmp/kro-aws-instances.yaml
rg -n "secretString|password|SecretString" argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/database-secret-mirror1-rg.yaml
```

The final `rg` command should not find any secret value injection. It may find documentation comments only if they are explicitly warning not to use `secretString`.

If a live cluster is available, verify:

```bash
kubectl get applicationset -n argocd ack-eventbridge
kubectl get applications -n argocd ack-eventbridge
kubectl get rule.eventbridge.services.k8s.aws -n <spoke-namespace>
kubectl get function.lambda.services.k8s.aws -n <spoke-namespace>
aws secretsmanager describe-secret --secret-id gen3-<spoke>-aurora-master-password
```

Do not run `aws secretsmanager get-secret-value` in logs or terminal transcripts unless debugging requires it and the output is fully suppressed.

## References To Verify During Implementation

- ACK EventBridge chart: `oci://public.ecr.aws/aws-controllers-k8s/eventbridge-chart`
- ACK Lambda chart: `oci://public.ecr.aws/aws-controllers-k8s/lambda-chart`
- EventBridge ACK API group: `eventbridge.services.k8s.aws`
- Lambda ACK API group: `lambda.services.k8s.aws`

At initial inspection on 2026-05-19, `helm show chart` reported:

- `eventbridge-chart` version `1.2.3`
- `lambda-chart` version `1.12.2`

Verify versions again before changing pinned chart versions.
