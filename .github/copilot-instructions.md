# gen3-kro — Copilot Custom Instructions

> Auto-loaded for **every** Copilot interaction in this workspace.

## Project Identity

gen3-kro is an **EKS Cluster Management Platform** — a CSOC (Central Security
Operations Center) EKS cluster that provisions and manages AWS infrastructure
across multiple spoke accounts via [KRO](https://kro.run) (Kube Resource
Orchestrator) and [ACK](https://aws-controllers-k8s.github.io/community/)
(AWS Controllers for Kubernetes), orchestrated by ArgoCD ApplicationSets.

gen3-kro supports **two deployment workflows**:
- **EKS CSOC** (primary): production EKS cluster deployed via Terraform +
  Terragrunt; ACK uses IRSA for AWS authentication
- **Local CSOC** (secondary): Kind cluster on the developer's laptop for
  RGD authoring and testing; ACK uses a K8s Secret for AWS authentication

The local Kind cluster mirrors gen3-kro's CSOC cluster structure — same
ArgoCD bootstrap chain, same sync-wave ordering, same RGD schema conventions —
so that ResourceGraphDefinitions authored locally can be promoted to EKS with
minimal change.

## Technology Stack

### EKS CSOC Workflow

| Component | Version | Purpose |
|-----------|---------|---------|
| Terraform | 1.13.5 | CSOC cluster, VPC, EKS, ArgoCD bootstrap |
| Terragrunt | 0.99.1 | Spoke IAM role management (host-side stack) |
| KRO | latest | Graph-based K8s resource orchestrator |
| ACK controllers (17+) | various | Kubernetes-native AWS resource management |
| ArgoCD | 7.7.16 | GitOps delivery |
| EKS | managed | The CSOC Kubernetes cluster |
| AWS CLI | 2.x | Authentication and AWS API access |
| kubectl | 1.35.1 | Cluster CLI |
| Helm | 3.16.1 | Package manager |

### Local CSOC Workflow (host-based, no container)

| Component | Version | Purpose |
|-----------|---------|---------|
| KRO | 0.9.0 | Graph-based K8s resource orchestrator |
| ACK controllers (13) | various | Kubernetes-native AWS resource management (→ real AWS) |
| ArgoCD | 7.7.16 | GitOps delivery |
| Kind | 0.27.0 | Local K8s cluster |
| AWS CLI | 2.x | Credential validation |
| kubectl | 1.35.1 | Cluster CLI |
| Helm | 3.16.1 | Package manager |

### ACK Controllers — Local CSOC

| Controller | Chart Version | ACK API Group |
|------------|--------------|---------------|
| acm | 1.3.5 | `acm.services.k8s.aws` |
| ec2 | 1.10.1 | `ec2.services.k8s.aws` |
| eks | 1.12.0 | `eks.services.k8s.aws` |
| elasticache | 1.3.3 | `elasticache.services.k8s.aws` |
| iam | 1.6.2 | `iam.services.k8s.aws` |
| kms | 1.2.2 | `kms.services.k8s.aws` |
| opensearchservice | 1.2.3 | `opensearchservice.services.k8s.aws` |
| rds | 1.7.7 | `rds.services.k8s.aws` |
| route53 | 1.3.1 | `route53.services.k8s.aws` |
| s3 | 1.3.2 | `s3.services.k8s.aws` |
| secretsmanager | 1.2.2 | `secretsmanager.services.k8s.aws` |
| sqs | 1.4.2 | `sqs.services.k8s.aws` |
| wafv2 | 1.2.1 | `wafv2.services.k8s.aws` |

## Directory Layout

```
gen3-kro/
├── .devcontainer/           # EKS workflow: VS Code DevContainer
├── .github/
│   ├── copilot-instructions.md      # This file (always-on)
│   └── instructions/                # Targeted instruction files (per glob)
├── argocd/
│   ├── addons/
│   │   ├── csoc/            # EKS CSOC addon values
│   │   └── local/           # Local CSOC addon definitions
│   ├── bootstrap/           # Entry-point ApplicationSets (EKS + local)
│   ├── charts/
│   │   ├── application-sets/  # Meta-chart: creates per-addon ApplicationSets
│   │   ├── instances/         # Helm chart for KRO CR instances
│   │   └── resource-groups/
│   │       └── templates/     # RGD YAML files (modular + capability tests)
│   └── cluster-fleet/
│       ├── spoke1/            # EKS spoke cluster overrides
│       └── local-aws-dev/     # Local CSOC per-cluster directories
│           ├── infrastructure/  # Production KRO CR instances
│           └── tests/           # KRO capability test instances
├── config/                  # User config (gitignored except examples)
├── docs/                    # Documentation, diagrams, design reports
├── iam/                     # Per-spoke IAM inline policies
├── scripts/                 # Deployment and orchestration scripts
├── terraform/               # CSOC cluster Terraform (container workflow)
└── terragrunt/              # Spoke IAM Terragrunt stack (host workflow)
```

## Coding Conventions

### Shell Scripts

- Always use `set -euo pipefail`
- **EKS scripts**: Use inline logging helpers (no external dependency)
- **Local CSOC scripts**: Use inline helpers (same pattern)
- Quote all variables: `"${var}"` not `$var`
- Use portable path resolution:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  ```

### KRO ResourceGraphDefinitions

- Use the KRO DSL: `string | required=true`, `integer | default=1`, `boolean | default=true`
- Status fields use optional chaining: `${resource.status.?field.orValue("loading")}`
- ACK readyWhen always checks both ARN and `ACK.ResourceSynced`:
  ```yaml
  readyWhen:
    - ${resource.status.?ackResourceMetadata.?arn.orValue('null') != 'null'}
    - ${resource.status.?conditions.orValue([]).exists(c, c.type == "ACK.ResourceSynced" && c.status == "True")}
  ```
- Always include ACK annotations on AWS resources:
  ```yaml
  annotations:
    services.k8s.aws/region: ${schema.spec.region}
    services.k8s.aws/adoption-policy: ${schema.spec.adoptionPolicy}
    services.k8s.aws/deletion-policy: ${schema.spec.deletionPolicy}
  ```

### Sync-Wave Ordering

All components follow this ArgoCD sync-wave ordering:

| Wave | Component |
|------|-----------|
| -30 | KRO controller (must register CRDs before any RGDs) |
| -20 | Bootstrap ApplicationSet |
| 1 | ACK controllers (→ real AWS APIs) |
| 10 | ResourceGraphDefinitions |
| 30 | KRO instances (infrastructure CRs) |

### Bootstrap Pattern

**EKS CSOC (primary):**
1. `scripts/install.sh apply` → Terraform creates EKS + ArgoCD + bootstrap ApplicationSet
2. Bootstrap ApplicationSet reads `argocd/bootstrap/` → creates region ApplicationSets
3. ApplicationSets render addons from `argocd/addons/csoc/addons.yaml`

**Local CSOC (host-based):**
1. `kind-local-test.sh install` → Helm installs ArgoCD directly
2. Creates ArgoCD cluster Secret (`fleet_member: control-plane`)
3. Applies bootstrap ApplicationSets (`local-addons`, `local-infra-instances`)
4. ArgoCD reconciles: application-sets chart → per-addon ApplicationSets → Applications

### AWS Credentials

**EKS CSOC:** ACK uses **IRSA** (IAM Roles for Service Accounts) — no long-lived keys.

**Local CSOC:** ACK uses a **K8s Secret** (`ack-aws-credentials`) injected from
`~/.aws/credentials`. Credentials are MFA-assumed-role (Tier 1) renewed by
`scripts/mfa-session.sh` on the host.

```bash
# Renew MFA credentials, then inject into Kind cluster:
bash scripts/kind-local-test.sh inject-creds
```

### AWS Account ID (Runtime Injection — Local CSOC)

The AWS account ID is **never stored in git**. It is resolved at runtime via
`aws sts get-caller-identity` and injected into the **ArgoCD cluster Secret**
as the `aws_account_id` annotation. ArgoCD propagates it through the bootstrap chain:
1. ArgoCD cluster Secret → `aws_account_id` annotation
2. ApplicationSet cluster generator → template variable
3. Instances Helm chart → `helm.parameters` value (`awsAccountId`)
4. Namespace annotation → `services.k8s.aws/owner-account-id`

RGDs read it via:
```yaml
${spokeNamespace.metadata.annotations['services.k8s.aws/owner-account-id']}
```

## Security — Never Commit Secrets

**NEVER** commit the following to git:
- AWS Account IDs (12-digit numbers)
- AWS Access Key IDs (`AKIA...`)
- AWS Secret Access Keys
- Session tokens, passwords, API keys
- Private keys or certificates
- Any ARNs containing account IDs

Instead, use:
- **Runtime injection** — resolve via AWS CLI and inject as K8s annotations/Secrets
- **Gitignored files** — use `config/shared.auto.tfvars.json` (already gitignored)
- **Placeholder values** — use `123456789012` for example account IDs in docs
- **ExternalSecrets** — pull secrets from AWS Secrets Manager at runtime

The `.gitignore` covers: `*.ppk`, `*.pem`, `**/secrets/*`, `config/*.json`
(except examples), `**/outputs/*`, `credentials`, `*.credentials`, `.aws/`.

## ResourceGraphDefinitions (RGDs)

RGDs use versioned naming: modular tier graphs use
`AwsGen3<Component><Version>` (e.g., `AwsGen3Foundation1`).

### Modular RGDs (Plan 02 Revision 5 — Foundation-heavy + Storage extraction)

| Tier | Category | RGD | Kind | Status | Depends On | Cost |
|------|----------|-----|------|--------|------------|------|
| 0 | Infra RGD | awsgen3foundation1 | AwsGen3Foundation1 | ✅ Built (31+ resources, S3 conditional) | — (standalone) | ~$37/mo |
| 0.5 | Infra RGD | awsgen3storage1 | AwsGen3Storage1 | ✅ Built (5 S3 buckets) | foundationBridge | ~$1-5/mo |
| 1 | Infra RGD | awsgen3database2 | AwsGen3Database2 | ✅ Built (thin + ESO) | databasePrepBridge | ~$45-350/mo |
| 2 | Infra RGD | awsgen3search1 | AwsGen3Search1 | ✅ Built (OpenSearch + conditional Redis) | searchPrepBridge + foundationBridge | ~$30-200/mo |
| 3 | Infra RGD | awsgen3compute2 | AwsGen3Compute2 | ✅ Built (Managed Nodegroups) | computePrepBridge + foundationBridge | ~$350/mo |
| 4 | Infra RGD | awsgen3iam1 | AwsGen3IAM1 | ✅ Built (11 IRSA roles) | Foundation + Compute + Storage bridges | ~$5/mo |
| 4 | Infra RGD | awsgen3messaging1 | AwsGen3Messaging1 | ✅ Built (SQS queues) | — (standalone) | ~$1/mo |
| 4.5 | Infra RGD | awsgen3clusterresources1 | AwsGen3ClusterResources1 | ✅ Built | computeBridge | ~$0 |
| 5 | App RGD | awsgen3helm2 | AwsGen3Helm2 | ✅ Built | All upstream bridges | ~$0 (pods) |
| 7 | Infra RGD | awsgen3advanced1 | AwsGen3Advanced1 | ✅ Built (WAFv2 WebACL) | — (standalone) | ~$5-10/mo |

Foundation1 absorbs ALL prep infrastructure (SGs, IAM roles, DB subnets, KMS keys)
behind feature flags (`databaseEnabled`, `computeEnabled`, `searchEnabled`).
S3 buckets are conditional via `storageEnabled` flag — when false, Storage1 tier
manages buckets instead. Foundation1 uses Test 8 dual-bridge pattern: `foundationBridge`
(with S3 ARNs) or `foundationBridgeNoStorage` (empty S3 ARNs), both writing to the
same ConfigMap name. Creates up to 5 bridge ConfigMaps: `foundationBridge` (always) +
`databasePrepBridge`, `computePrepBridge`, `searchPrepBridge` (conditional) +
`acmBridge` (always, placeholder or real cert).

Storage1 creates 3-5 S3 buckets (logging, data, upload + conditional manifest,
dashboard) and exports a `storageBridge` ConfigMap with bucket ARNs and names.

IAM1 provides 11 IRSA roles: 7 per-service (fence, audit, hatchery, manifestservice,
externalSecrets, aws-es-proxy, ssjdispatcher) + 4 cluster-level (ALB controller,
S3 CSI driver, Karpenter, dashboard). Messaging1 provides SQS queues.

Search1 includes conditional ElastiCache Redis (replication group + SG + subnet group)
controlled by `redisEnabled` flag, with dual searchBridge pattern for redis endpoint.

Advanced1 provides a WAFv2 WebACL with AWS managed rules (OWASP, bad inputs, SQLi).
CloudFront is out of scope (no ACK controller available).

Observability: Gen3 implements its own observability via Grafana Alloy → Loki/Mimir/Tempo.
No separate Observability RGD is needed — the application handles logging and metrics.

Helm2 reads ALL upstream bridges including storageBridge (bucket names) and
advancedBridge (WAF ACL ARN). Supports `dbCreateEnabled` for auto DB provisioning
via gen3-helm init containers.

## KRO Capability Tests

All KRO feature-validation tests live in `argocd/charts/resource-groups/templates/`
and are ArgoCD-managed — no manual `kubectl apply`. Instances are declared in
`argocd/cluster-fleet/local-aws-dev/tests/`.

| # | Kind | RGD file | Instance key(s) | Resources | AWS? |
|---|------|----------|-----------------|-----------|------|
| 1 | `KroForEachTest` | `krotest01-foreach-rg.yaml` | `kro-foreach-basic`, `kro-foreach-cartesian` | ConfigMaps | No |
| 2 | `KroIncludeWhenTest` | `krotest02-includewhen-rg.yaml` | `kro-includewhen-minimal`, `kro-includewhen-full` | ConfigMaps | No |
| 3 | `KroBridgeProducer` | `krotest03-bridge-producer-rg.yaml` | `kro-bridge-producer` | ConfigMaps + Secret | No |
| 4 | `KroBridgeConsumer` | `krotest04-bridge-consumer-rg.yaml` | `kro-bridge-consumer` | ConfigMaps | No |
| 5 | `KroCELTest` | `krotest05-cel-expressions-rg.yaml` | `kro-cel-dev`, `kro-cel-prod` | ConfigMaps | No |
| 6 | `KroTest06SgConditional` | `krotest06-sg-conditional-rg.yaml` | `kro-sg-base-only`, `kro-sg-all-features` | ACK EC2 | Yes |
| 7a | `KroTest07Producer` | `krotest07a-cross-rgd-producer-rg.yaml` | `kro-crossrgd-producer` | ACK EC2 | Yes |
| 7b | `KroTest07Consumer` | `krotest07b-cross-rgd-consumer-rg.yaml` | `kro-crossrgd-consumer` | ACK EC2 | Yes |
| 8 | `KroChainedOrValueTest` | `krotest08-chained-orvalue-rg.yaml` | `kro-chained-orvalue-*` | ConfigMaps | No |

**Key findings from capability tests:**
- Test 6: KRO cannot add conditional entries within a single array (e.g., `ingressRules`).
  Use Pattern A — multiple separate resources with `includeWhen`, one per tier.
- Test 7: Cross-RGD status values flow via bridge ConfigMap + `externalRef`.
- Test 8: KRO silently drops any expression referencing an excluded resource even with
  optional chaining. Use conditional duplicate resources with opposite `includeWhen`.
