# Pending AWS Resource Creations for Spoke1 Gen3 Deployment

## Executive Summary

- **Secrets to Create:** 11 AWS Secrets Manager secrets (1 existing, 10 new)
- **RDS Database:** Will be auto-created by Database1 RGD ✅
- **S3 Buckets:** Will be auto-created by Storage1 RGD ✅
- **Route53 Hosted Zone:** Already exists, will be adopted by DNS1 RGD ✅
- **IAM Roles:** Will be auto-created by Platform/App-IAM1 RGDs ✅
- **EKS Cluster:** Will be auto-created by Compute1 RGD ✅
- **VPC/Networking:** Will be auto-created by Network1 RGD ✅
- **Issues Found:** ✅ **NONE** (graph connections verified, no blocking dependencies)

---

## Part A: Secrets Manager Secrets (MANUAL CREATION REQUIRED)

### Pre-Deployment: Aurora Master Password

**Status:** Partially exists (as `spoke1-aurora-master-password`; needs update to `gen3-aurora-master-password`)

**Action Required:**
```bash
# EITHER: Update existing secret to new name
aws secretsmanager create-secret \
  --name gen3-aurora-master-password \
  --region us-east-1 \
  --secret-string '{
    "username": "postgres",
    "password": "YOUR_STRONG_PASSWORD",
    "host": "aurora-cluster-endpoint.c9akciq32.us-east-1.rds.amazonaws.com",
    "port": "5432"
  }' \
  --tags "Key=Application,Value=Gen3" "Key=Environment,Value=spoke1" "Key=Tier,Value=database"

# OR: Use Systems Manager Parameter Store if AWS Secrets Manager is not available
aws ssm put-parameter \
  --name /gen3/aurora-master-password \
  --type SecureString \
  --value 'postgres_password' \
  --region us-east-1
```

**Schema Required:**
```json
{
  "username": "postgres",
  "password": "<STRONG_PASSWORD>",
  "host": "<aurora-cluster-endpoint>.rds.amazonaws.com",
  "port": "5432"
}
```

**Timeline:** Create BEFORE Database1 RGD finishes (RGD reads this secret during init)

---

### Auto-Created by PushSecret: Service DB Credentials

**Services (8 total):**

| Service | Secret Name | Status | Created By |
|---------|-------------|--------|-----------|
| Arborist | `gen3-arborist-creds` | Will be auto-created | PushSecret (first pod init) |
| Audit | `gen3-audit-creds` | Will be auto-created | PushSecret (first pod init) |
| Fence | `gen3-fence-creds` | Will be auto-created | PushSecret (first pod init) |
| Indexd | `gen3-indexd-creds` | Will be auto-created | PushSecret (first pod init) |
| Metadata | `gen3-metadata-creds` | Will be auto-created | PushSecret (first pod init) |
| Peregrine | `gen3-peregrine-creds` | Will be auto-created | PushSecret (first pod init) |
| Sheepdog | `gen3-sheepdog-creds` | Will be auto-created | PushSecret (first pod init) |
| WTS | `gen3-wts-creds` | Will be auto-created | PushSecret (first pod init) |

**How PushSecret Works:**
1. Helm chart creates a Kubernetes Secret with service credentials (random password)
2. ExternalSecrets PushSecret controller detects the Secret
3. PushSecret pushes the K8s Secret to AWS Secrets Manager with name `gen3-{service}-creds`
4. Future deployments pull from AWS Secrets Manager instead of Helm-generated local Secret

**Required IAM Permissions** (in app-iam1-rg.yaml externalSecretsRole):
```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:CreateSecret",
    "secretsmanager:PutSecretValue",
    "secretsmanager:UpdateSecret",
    "secretsmanager:TagResource",
    "secretsmanager:ListSecrets"
  ],
  "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:gen3-*"
}
```

**Timeline:** Auto-created during app-helm1 deployment (first pod startup)

---

### Optional: WTS OAuth Secrets

**Services (2):**

| Secret | Schema | Status |
|--------|--------|--------|
| `gen3-wts-g3auto` | WTS g3auto credentials | Create manually if WTS is enabled |
| `gen3-wts-oidc-client` | WTS OIDC client config | Create manually if WTS is enabled |

**Action (if WTS is enabled):**
```bash
aws secretsmanager create-secret \
  --name gen3-wts-g3auto \
  --region us-east-1 \
  --secret-string '{
    "client_id": "wts_client_id",
    "client_secret": "wts_secret_hash",
    "endpoint": "https://wts.example.com"
  }'

aws secretsmanager create-secret \
  --name gen3-wts-oidc-client \
  --region us-east-1 \
  --secret-string '{
    "client_id": "oidc_client_id",
    "client_secret": "oidc_secret",
    "issuer": "https://oidc-provider.example.com"
  }'
```

**Timeline:** Create BEFORE Gen3 pods start (if WTS is enabled)
**Current Status in spoke1:** WTS is enabled ✅

---

## Part B: RDS Aurora Database

**Status:** ✅ Will be created by Database1 RGD (sync-wave 15)

**Auto-Created Configuration:**
- **Engine:** PostgreSQL 16.6
- **Mode:** Aurora Serverless v2 (auto-scaling)
- **Capacity:** 0.5-4 Aurora Capacity Units (ACU)
- **Instances:** 1 writer (serverless, no manual provisioning)
- **Master User:** `postgres`
- **Master Password:** Read from `gen3-aurora-master-password` secret
- **Initial Database:** `gen3`
- **Encryption:** SSE-S3 (default; can be upgraded to KMS)
- **Backup Retention:** 7 days (RDS default)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/database1-rg.yaml`
**Bridge Output:** `database-bridge` ConfigMap in `spoke1` namespace

**No Manual Action Required** ✅

---

## Part C: S3 Buckets

**Status:** ✅ Will be created by Storage1 RGD (sync-wave 15)

**Auto-Created Buckets:**

| Bucket Name | Purpose | Versioning | Encryption | Public Access |
|-------------|---------|-----------|-----------|----------------|
| `gen3-spoke1-logging` | Log aggregation target | Enabled | SSE-S3 | Blocked ✅ |
| `gen3-spoke1-data` | Data downloads/metadata | Enabled | SSE-S3 | Blocked ✅ |
| `gen3-spoke1-upload` | File uploads (transient) | Enabled | SSE-S3 | Blocked ✅ |
| `gen3-spoke1-usersync` | Fence user.yaml sync | Enabled | SSE-S3 | Blocked ✅ |

**NOT Created** (intentionally disabled):
- `manifestBucketName: ""` → ManifestService disabled
- `dashboardBucketName: ""` → Portal disabled

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/storage1-rg.yaml`
**Bridge Output:** `storage-bridge` ConfigMap in `spoke1` namespace

**No Manual Action Required** ✅

---

## Part D: Route53 Hosted Zone

**Status:** ✅ Already exists; will be adopted by DNS1 RGD

**Current Configuration:**
- **Zone Name:** `rds-pla.net`
- **Zone ID:** `/hostedzone/Z095986738M5ANBGDR7OG`
- **Adoption Policy:** `retain` (won't be deleted if RGD is removed)

**Auto-Managed DNS Records** (created by DNS1 RGD):
- `spoke1dev.rds-pla.net` → ALB endpoint (via ExternalDNS)
- CNAME records as needed for services

**Adoption Method:** DNS1 RGD uses `services.k8s.aws/adoption-fields` with zone name

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase0/domain-security-rg.yaml`

**No Manual Action Required** ✅

---

## Part E: ACM Certificate

**Status:** ✅ Will be created/adopted by Domain-Security RGD

**Auto-Managed Certificate:**
- **Domain:** `spoke1dev.rds-pla.net`
- **Validation:** DNS (automated via Route53)
- **Auto-Renewal:** Enabled
- **Use:** ALB listener (HTTPS/443)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase0/domain-security-rg.yaml`
**Bridge Output:** `dns-bridge` ConfigMap with certificate ARN

**No Manual Action Required** ✅

---

## Part F: EKS Cluster

**Status:** ✅ Will be created by Compute1 RGD (sync-wave 15)

**Auto-Created Configuration:**
- **Kubernetes Version:** 1.35
- **Auto Mode:** Enabled (managed node pools + auto-scaling)
- **Node Pools:** `general-purpose`, `system`
- **Node Type:** `m5.large`
- **Desired Size:** 2 nodes
- **Min Size:** 1 node
- **Max Size:** 5 nodes
- **Disk Size:** 20 GB per node
- **OIDC Provider:** Auto-created for IRSA
- **Logging:** CloudWatch (control plane + worker logs)
- **Encryption:** EKS secret encryption enabled

**Networking:**
- **VPC:** `172.0.0.0/16` (from infrastructure-values)
- **Public Subnets:** 2 (for ALB/NAT)
- **Private Subnets:** 2 (for pods)
- **DB Subnets:** 2 (for RDS)
- **Security Groups:** Auto-managed (node SG + pod SG)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/compute1-rg.yaml`
**Bridge Output:** `compute-bridge` ConfigMap with cluster endpoint, OIDC provider ARN, CA certificate

**No Manual Action Required** ✅

---

## Part G: IAM Roles (IRSA - Identity and Access Management)

**Status:** ✅ Will be created by Platform/App-IAM1 RGDs (sync-wave 25)

### Platform Addon Roles (4 roles)

| Role | Service Account | Permissions | Created By |
|------|------------------|-------------|-----------|
| `gen3-alb-controller-role` | `aws-load-balancer-controller` (kube-system) | ALB/NLB management | platform-iam1-rg.yaml |
| `gen3-s3-csi-driver-role` | `ebs-csi-controller-sa` (kube-system) | S3 bucket mounting | platform-iam1-rg.yaml |
| `gen3-karpenter-role` | `karpenter-sa` (karpenter) | EC2 node creation | platform-iam1-rg.yaml |
| `gen3-external-dns-role` | `external-dns-sa` (kube-system) | Route53 DNS management | platform-iam1-rg.yaml |

### Application Service Roles (8 roles)

| Role | Service Account | Permissions | Created By |
|------|------------------|-------------|-----------|
| `gen3-fence-role` | `fence-sa` (gen3) | S3 read/write (data, upload, users) | app-iam1-rg.yaml |
| `gen3-audit-role` | `audit-sa` (gen3) | CloudWatch logs | app-iam1-rg.yaml |
| `gen3-hatchery-role` | `hatchery-sa` (gen3) | EC2 instance management | app-iam1-rg.yaml |
| `gen3-manifestservice-role` | `manifestservice-sa` (gen3) | (no permissions; disabled) | app-iam1-rg.yaml |
| `gen3-external-secrets-role` | `external-secrets-sa` (gen3) | Secrets Manager read + write | app-iam1-rg.yaml |
| `gen3-aws-es-proxy-role` | `aws-es-proxy-sa` (gen3) | OpenSearch HTTP access | app-iam1-rg.yaml |
| `gen3-ssjdispatcher-role` | `ssjdispatcher-sa` (gen3) | SQS + S3 data bucket | app-iam1-rg.yaml |
| `gen3-dashboard-role` | `dashboard-sa` (gen3) | S3 dashboard bucket read | app-iam1-rg.yaml |

**Trust Relationship:** Each role trusts OIDC provider (EKS OpenID Connect provider)

**Output Bridge:** `app-iam-bridge` and `platform-iam-bridge` ConfigMaps with role ARNs

**Created By:**
- `argocd/csoc/kro/aws-rgds/gen3/v1/Phase2/platform-iam1-rg.yaml`
- `argocd/csoc/kro/aws-rgds/gen3/v1/Phase2/app-iam1-rg.yaml`

**No Manual Action Required** ✅

---

## Part H: VPC & Networking Infrastructure

**Status:** ✅ Will be created by Network-Security1 RGD (sync-wave 1)

**Auto-Created Components:**
- **VPC:** `172.0.0.0/16` with auto-assigned default CIDR
- **Subnets:** 6 total across 2 AZs:
  - 2 Public (for ALB, NAT Gateway) — `172.0.240-241.0/24`
  - 2 Private (for pods) — `172.0.0-16.0/20`
  - 2 Database (for RDS) — `172.0.32-33.0/24`
- **NAT Gateway:** Auto-created in public subnets
- **Internet Gateway:** Auto-created and attached
- **Route Tables:** Public, private, DB
- **Security Groups:** Node SG, pod SG, RDS SG, ALB SG
- **Network ACLs:** Default managed by AWS

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase0/network-security1-rg.yaml`

**No Manual Action Required** ✅

---

## Part I: SQS Message Queues

**Status:** ✅ Will be created by Messaging1 RGD (sync-wave 1)

**Auto-Created Queues:**
- Message Retention: 345,600 seconds (4 days)
- Visibility Timeout: 300 seconds (5 minutes)
- Encryption: SSE (AWS managed)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase0/messaging1-rg.yaml`

**No Manual Action Required** ✅

---

## Part J: OpenSearch Domain

**Status:** ✅ Will be created by Search1 RGD (IF enabled; currently disabled in spoke1)

**Current Status in spoke1:** Search1 RGD not enabled (compute.openSearchDomain excluded)

**If Enabled, Auto-Created Configuration:**
- **Engine:** OpenSearch 2.11
- **Instance Type:** `t3.small.search` (development size)
- **Instance Count:** 1 node
- **Volume:** 10 GB GP3 storage
- **Encryption:** AWS managed (EBS)
- **Public Access:** Disabled (VPC-only)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Phase1/compute1-rg.yaml` (if enabled)

**No Manual Action Required (Currently Disabled)** ✅

---

## Part K: WAF Web ACL

**Status:** Will be created by Advanced1 RGD (IF enabled; currently disabled)

**Current Status in spoke1:** WAFv2 disabled in infrastructure-values.yaml (`wafEnabled: "false"`)

**If Enabled, Auto-Created Rules:**
- AWS Managed Rules (OWASP, bad inputs, SQLi protection)
- Rate limiting (5000 requests per 5 minutes per IP)
- Geo-blocking (if configured)

**Created By:** `argocd/csoc/kro/aws-rgds/gen3/v1/Advanced/advanced1-rg.yaml` (if enabled)

**No Manual Action Required (Currently Disabled)** ✅

---

## Summary Table: All AWS Resources

| Resource | Type | Status | Manual Action | Auto-Created | Notes |
|----------|------|--------|---------------|--------------|-------|
| **Aurora Database** | RDS | ✅ | None | Phase 1 (Wave 15) | Serverless v2, auto-scaling |
| **S3 Buckets (4)** | Storage | ✅ | None | Phase 1 (Wave 15) | Logging, data, upload, usersync |
| **Route53 Zone** | DNS | ✅ | None | Phase 0 (Wave -20) | Adoption of existing zone |
| **ACM Certificate** | Security | ✅ | None | Phase 0 (Wave -20) | DNS validation via Route53 |
| **EKS Cluster** | Compute | ✅ | None | Phase 1 (Wave 15) | Auto mode with Karpenter |
| **VPC + Subnets** | Networking | ✅ | None | Phase 0 (Wave 1) | 6 subnets across 2 AZs |
| **Security Groups** | Networking | ✅ | None | Phase 0 (Wave 1) | Node, pod, RDS, ALB SGs |
| **NAT Gateway** | Networking | ✅ | None | Phase 0 (Wave 1) | For private subnet egress |
| **IAM Roles (12)** | IAM | ✅ | None | Phase 2 (Wave 25) | IRSA for pods + addons |
| **SQS Queues** | Messaging | ✅ | None | Phase 0 (Wave 1) | Gen3 job queues |
| **Secrets Manager Secrets (11)** | Secrets | ⚠️ | **YES - Manual** | Partial (8 via PushSecret) | 1 pre-existing, 10 new |
| **OpenSearch** | Search | ❌ Disabled | None | N/A | Not enabled in spoke1 |
| **WAF Web ACL** | Security | ❌ Disabled | None | N/A | Not enabled in spoke1 |

---

## Critical Path: Deployment Prerequisites

### MUST CREATE BEFORE ArgoCD Enable:

1. ✅ AWS Account with credentials configured
2. ✅ VPC (will be auto-created by Network1 RGD)
3. ✅ Route53 Hosted Zone (already exists: `rds-pla.net`)

### MUST CREATE BEFORE App-Helm1 Sync:

1. ⚠️ **`gen3-aurora-master-password` Secret** — Required by Database1 RGD to initialize Aurora
2. ⚠️ **`gen3-wts-*` Secrets (2)** — Required by WTS pod startup (if WTS is enabled)

### AUTO-CREATED DURING DEPLOYMENT:

1. ✅ Service DB credentials (`gen3-{service}-creds`) — Created by PushSecret
2. ✅ All RDS, S3, EKS, IAM, networking resources

---

## Deployment Timeline

```
ArgoCD Enable
  ↓ (Wave -30)
KRO Controller CRDs installed
  ↓ (Wave -20)
Bootstrap ApplicationSet creates per-addon ApplicationSets
  ↓ (Wave 1) [REQUIRES: gen3-aurora-master-password secret in AWS]
Phase 0: Network, DNS, Messaging RGDs sync
  ├→ VPC, subnets, security groups created
  ├→ Route53 zone adopted, ACM certificate created
  └→ SQS queues created
  ↓ (Wave 15) [REQUIRES: gen3-aurora-master-password secret already created]
Phase 1: Storage, Database, Compute RGDs sync
  ├→ S3 buckets created
  ├→ Aurora database created (reads master password from Secrets Manager)
  └→ EKS cluster created
  ↓ (Wave 25)
Phase 2: IAM RGDs sync
  ├→ Platform addon IAM roles created
  └→ App service IAM roles created
  ↓ (Wave 30)
Phase 3: Platform Helm RGD syncs
  ├→ Spoke cluster registered in CSOC ArgoCD
  └→ Cluster-level-resources Application syncs (installs addons: external-secrets, external-dns, etc.)
  ↓ (Wave 35) [REQUIRES: gen3-wts-* secrets if WTS enabled]
Phase 4: App-Helm RGD syncs
  ├→ Gen3 Application registered in CSOC ArgoCD
  └→ Gen3 workloads deploy to spoke cluster (fence, sheepdog, etc.)
  ↓ (Ongoing)
PushSecret Controller
  ├→ Detects K8s Secrets created by Helm
  └→ Pushes to AWS Secrets Manager (gen3-{service}-creds)
  ↓
Steady State
  └→ All pods running, ExternalSecrets pulling from AWS Secrets Manager
```

---

## Verification Checklist

After deployment, verify:

- [ ] `kubectl get configmap -n spoke1 | grep bridge` → All 8+ bridge ConfigMaps present
- [ ] `kubectl get awsgen3* -n spoke1` → All instances ready
- [ ] `kubectl get secretstore -n gen3` → SecretStore created
- [ ] `kubectl get externalsecret -n gen3` → ExternalSecrets synced
- [ ] `aws rds describe-db-clusters` → Aurora cluster exists
- [ ] `aws s3 ls` → All 4 buckets present
- [ ] `aws iam list-roles` → All 12 IRSA roles present
- [ ] `aws secretsmanager list-secrets` → gen3-* secrets present
- [ ] `kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns` → DNS records syncing
- [ ] `kubectl get ingress -n gen3` → ALB ingress created
- [ ] Gen3 pods running: `kubectl get pods -n gen3`

---

**Report Generated:** 2026-05-12
**Deployment Readiness:** ✅ Ready to proceed with prerequisite checklist
