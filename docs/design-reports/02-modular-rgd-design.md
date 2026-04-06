# Gen3 Modular RGD Design

> Purpose: Define a set of ResourceGraphDefinitions (RGDs) and Helm-deployed
> tiers that can be deployed independently or composed together for a full
> Gen3 environment. Infrastructure RGDs produce AWS resources via ACK.
> Application and observability tiers deploy workloads on EKS via gen3-helm.
> Cross-tier data flows via bridge ConfigMaps (K8s ConfigMaps + externalRef).
>
> **Revision 4** — Fundamental tier redistribution. Foundation (Tier 0) now
> contains ALL preparatory infrastructure (networking, IAM, KMS, SGs, DB
> subnets, subnet groups) with `includeWhen` feature flags. Tiers 1–3 become
> thin graphs containing ONLY the expensive managed services (Aurora,
> OpenSearch, EKS). Added conditional per-capability bridge ConfigMaps.
> Detailed security group configurations and EKS cluster resource variants.
> Unified v1 naming: Foundation1, Database1, Compute1.
> See prior revisions in git history.

---

## 1. Design Principles

1. **Foundation-heavy, services-thin** — Tier 0 (Foundation) contains ALL
   preparatory infrastructure: networking, subnets, route tables, KMS keys,
   IAM roles, security groups, S3 buckets, and DB subnet groups. Tiers 1–3
   contain ONLY the expensive managed services themselves (Aurora, OpenSearch,
   EKS). This means Tier 0 is the minimum viable infrastructure for Gen3 —
   deploying it alone validates the entire networking/IAM/encryption backbone.
2. **Feature-flag composition** — Foundation exposes `databaseEnabled`,
   `computeEnabled`, and `searchEnabled` boolean flags. Each controls a set
   of conditional resources (`includeWhen`) and a corresponding per-capability
   bridge ConfigMap. Downstream tiers read their prep bridge to get pre-built
   subnets, SGs, KMS keys, and IAM roles without creating them.
3. **No duplication** — A resource appears in exactly one RGD. Higher tiers
   reference, never recreate.
4. **Versatility over cost** — RGD size does not matter. A 35-resource
   Foundation is preferred over splitting into 5 small graphs, because it
   keeps all prep infra in one reconciliation unit with a single bridge output.
5. **Resource variants via includeWhen** — KRO cannot conditionally add/remove
   fields within a single resource (e.g., inline array entries). When a
   managed service has genuinely different spec shapes (EKS Standard vs Auto
   Mode), create separate resource definitions guarded by `includeWhen`.
6. **Versioned naming** — `AwsGen3<Component><Version>` format. All production
   RGDs use v1 naming. Breaking CRD changes require version bumps.
7. **Infrastructure / Application separation** — RGDs (Tiers 0–4, 7) manage
   AWS infrastructure via ACK. Helm charts (Tiers 5–6) deploy application
   workloads on EKS. ArgoCD orchestrates both.

---

## 2. RGD Tier Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DEPLOYMENT OPTIONS                             │
│                                                                         │
│  Infra-only:     T0                                          (~$37/mo)  │
│  Dev + DB:       T0(db) → T1                                 (~$80/mo)  │
│  Dev + Search:   T0(db,search) → T1 → T2                    (~$130/mo)  │
│  Full Infra:     T0(db,search,compute) → T1 → T2 → T3 → T4 (~$480/mo)   │
│  Full Platform:  T0(all) → T1 → T2 → T3 → T4 → T5 → T6     (~$500+/mo)  │
│  Hardened:       T0(all) → T1 → T2 → T3 → T4 → T5 → T6 → T7(~$700+/mo)  │
│                                                                         │
│  Test Graph:     AwsGen3Test1Flat (monolithic, no EKS/Aurora) (~$37/mo) │
│                                                                         │
│  T0(flag): Foundation with feature flags enabled                        │
└─────────────────────────────────────────────────────────────────────────┘

  INFRASTRUCTURE TIERS (RGD-managed via ACK)
  ──────────────────────────────────────────
  Tier 0: Foundation         VPC, networking, KMS, IAM, SGs, S3,        ~$37/mo
                             + conditional DB/compute/search prep
  Tier 1: Database           Aurora cluster + instance(s) only          ~$45-350/mo
  Tier 2: Search             OpenSearch domain only                     ~$26-50/mo
  Tier 3: Compute            EKS cluster + nodegroup/auto-mode only     ~$350/mo
  Tier 4: Application IAM    IRSA roles, SQS, Secrets Manager           ~$5/mo

  APPLICATION TIERS (Helm-deployed on EKS)
  ────────────────────────────────────────
  Tier 5: Application        gen3-helm umbrella chart (14+ services)    ~$0 (pods)
  Tier 6: Observability      LGTM stack (Grafana/Loki/Mimir/Alloy)     ~$5-15/mo

  OPTIONAL INFRASTRUCTURE (RGD-managed)
  ─────────────────────────────────────
  Tier 7: Advanced & Mon.    WAF, EFS, ElastiCache, CloudWatch, SNS     variable
```

### Key Architectural Change (v3 → v4)

The previous design distributed preparatory infrastructure across tiers:
Database subnets/SGs/KMS in Tier 1, EKS IAM/SGs in Tier 3. This created
**deep coupling** — each service tier duplicated networking/IAM patterns
and required its own VPC references.

The new design centralizes ALL prep infrastructure in Tier 0 and exports
per-capability bridge ConfigMaps. Downstream tiers become thin consumers:

```
Tier 0 (Foundation)
├── Always: VPC, IGW, NAT, EIP, subnets, RTs, KMS (logging+platform), S3
├── includeWhen: databaseEnabled
│     DB subnets, DB RT, DB subnet group, DB KMS key, Aurora SG
│     → databasePrepBridge ConfigMap
├── includeWhen: computeEnabled
│     Cluster IAM role, Node IAM role, EKS SG
│     → computePrepBridge ConfigMap
└── includeWhen: searchEnabled
      Search KMS key, OpenSearch SG
      → searchPrepBridge ConfigMap

Tier 1 (Database) ← reads databasePrepBridge
    Aurora cluster + instance(s) ONLY

Tier 2 (Search)   ← reads searchPrepBridge
    OpenSearch domain ONLY

Tier 3 (Compute)  ← reads computePrepBridge + foundationBridge
    EKS cluster + nodegroup/auto-mode ONLY
```

---

## 3. Tier Definitions

### Tier 0: Foundation — `AwsGen3Foundation1`

**Purpose**: Complete infrastructure backbone for Gen3. Contains all networking,
encryption, IAM, security groups, and storage. Feature flags control which
downstream-tier preparatory resources are provisioned. This is the **minimum
viable Gen3 infrastructure** — deploying Tier 0 alone validates the entire
AWS backbone without incurring managed-service costs.

**Version note**: `AwsGen3Foundation1` (revised) replaces the original
simpler Foundation. The original had no feature flags or conditional resources — it created only the
base networking/KMS/S3 layer. The revised version absorbs all preparatory resources from
Database, Compute, and Search tiers.

#### Always-Present Resources (16)

| 4 | `eip1` | ElasticIPAddress | Static IP for NAT Gateway |
| 5 | `publicRouteTable` | RouteTable | IGW route (`0.0.0.0/0 → IGW`) |
| 6 | `publicSubnet1` | Subnet | Public AZ-a (ALB, NAT Gateway) |
| 7 | `publicSubnet2` | Subnet | Public AZ-b (ALB redundancy) |
| 8 | `natGateway1` | NATGateway | Private subnet internet egress |
| 9 | `privateRouteTable` | RouteTable | NAT route (`0.0.0.0/0 → NAT`) |
| 10 | `privateSubnet1` | Subnet | Private AZ-a (EKS nodes, general workloads) |
| 11 | `privateSubnet2` | Subnet | Private AZ-b (EKS nodes, general workloads) |
| 12 | `loggingKey` | KMS Key | Encrypt logs, S3 access logs |
| 13 | `platformKey` | KMS Key | Encrypt EKS secrets, application data (EKS service grant) |
| 14 | `loggingBucket` | S3 Bucket | Centralized logging (encrypted with loggingKey) |
| 15 | `dataBucket` | S3 Bucket | Gen3 data objects (encrypted with platformKey) |
| 16 | `uploadBucket` | S3 Bucket | Upload staging (encrypted with platformKey) |

#### Database Prep Resources (7, `includeWhen: databaseEnabled`)

| # | Resource ID | Kind | Purpose |
|---|------------|------|---------|
| 17 | `dbRouteTable` | RouteTable | DB subnet routing (`0.0.0.0/0 → NAT`) |
| 18 | `dbSubnet1` | Subnet | Database AZ-a (Aurora placement) |
| 19 | `dbSubnet2` | Subnet | Database AZ-b (Aurora placement) |
| 20 | `dbSubnetGroup` | DBSubnetGroup | RDS subnet placement (references dbSubnet1 + dbSubnet2) |
| 21 | `databaseKey` | KMS Key | Encrypt Aurora at rest (RDS service policy) |
| 22 | `auroraSg` | SecurityGroup | Port 5432 from VPC CIDR (see SG details below) |
| 23 | `databasePrepBridge` | ConfigMap | Bridge with DB prep outputs (6 fields) |

#### Compute Prep Resources (4, `includeWhen: computeEnabled`)

| # | Resource ID | Kind | Purpose |
|---|------------|------|---------|
| 24 | `clusterRole` | IAM Role | EKS cluster service role (trust: `eks.amazonaws.com`) |
| 25 | `nodeRole` | IAM Role | EKS node group role (trust: `ec2.amazonaws.com`) |
| 26 | `eksSecurityGroup` | SecurityGroup | EKS API 443 + kubelet 10250 from VPC CIDR |
| 27 | `computePrepBridge` | ConfigMap | Bridge with compute prep outputs (3 fields) |

#### Search Prep Resources (3, `includeWhen: searchEnabled`)

| # | Resource ID | Kind | Purpose |
|---|------------|------|---------|
| 28 | `searchKey` | KMS Key | Encrypt OpenSearch at rest (opensearch service policy) |
| 29 | `openSearchSg` | SecurityGroup | Port 443 from VPC CIDR (HTTPS to OpenSearch) |
| 30 | `searchPrepBridge` | ConfigMap | Bridge with search prep outputs (2 fields) |

#### Foundation Bridge (always present)

| # | Resource ID | Kind | Purpose |
|---|------------|------|---------|
| 31 | `foundationBridge` | ConfigMap | Bridge with base networking/storage outputs (16 fields) |

**Total: 31 resources** (16 always + 7 database + 4 compute + 3 search + 1 bridge)

#### Why Separate Per-Capability Bridges?

KRO builds a dependency DAG from CEL expressions. If the `foundationBridge`
ConfigMap referenced `${eksSecurityGroup.status.?id}`, KRO would create a
dependency edge from the bridge to `eksSecurityGroup`. When `computeEnabled`
is false, `eksSecurityGroup` is excluded by `includeWhen` — but the dependency
still exists, causing a resolution failure.

The solution is **per-capability bridge ConfigMaps**, each guarded by the same
`includeWhen` condition as the resources it references. Foundation's always-present
bridge only references always-present resources.

#### Security Group Configurations

All security groups use **VPC CIDR-based rules** (not SG-to-SG userIDGroupPairs).
This avoids cross-resource dependencies between conditional SGs and is compatible
with any combination of feature flags. See Plan 04 for the pattern analysis.

**`eksSecurityGroup`** (includeWhen: `computeEnabled`):
```yaml
ingressRules:
  - ipProtocol: tcp
    fromPort: 443
    toPort: 443
    ipRanges:
      - cidrIP: ${schema.spec.vpcCIDR}
        description: "HTTPS API server access from VPC"
  - ipProtocol: tcp
    fromPort: 10250
    toPort: 10250
    ipRanges:
      - cidrIP: ${schema.spec.vpcCIDR}
        description: "Kubelet API from VPC"
```

**`auroraSg`** (includeWhen: `databaseEnabled`):
```yaml
ingressRules:
  - ipProtocol: tcp
    fromPort: 5432
    toPort: 5432
    ipRanges:
      - cidrIP: ${schema.spec.vpcCIDR}
        description: "PostgreSQL from VPC"
```

**`openSearchSg`** (includeWhen: `searchEnabled`):
```yaml
ingressRules:
  - ipProtocol: tcp
    fromPort: 443
    toPort: 443
    ipRanges:
      - cidrIP: ${schema.spec.vpcCIDR}
        description: "HTTPS to OpenSearch from VPC"
```

> **Production hardening (future)**: A Foundation v3 could replace VPC CIDR rules
> with `userIDGroupPairs` for SG-to-SG references (e.g., Aurora SG allows only
> traffic from EKS SG). This requires all SGs to be unconditional or uses SG
> variant resources with mutual includeWhen guards
> (e.g., `auroraSgWithEks` when `databaseEnabled && computeEnabled`).
> This adds complexity with no functional benefit for dev/staging — VPC CIDR
> is sufficient for intra-VPC traffic control.

#### IAM Role Configurations

**`clusterRole`** (includeWhen: `computeEnabled`):
Trust: `eks.amazonaws.com` → `[sts:AssumeRole, sts:TagSession]`
Managed policies:
- `AmazonEKSClusterPolicy`
- `AmazonEKSVPCResourceController`
- `AmazonEKSComputePolicy` (required for Auto Mode)
- `AmazonEKSBlockStoragePolicy` (required for Auto Mode)
- `AmazonEKSLoadBalancingPolicy` (required for Auto Mode)
- `AmazonEKSNetworkingPolicy` (required for Auto Mode)

> All 6 policies are attached regardless of Standard vs Auto Mode. The extra 4
> policies are no-ops when Auto Mode is not enabled, but pre-attaching them
> means switching to Auto Mode later requires no IAM changes.

**`nodeRole`** (includeWhen: `computeEnabled`):
Trust: `[ec2.amazonaws.com, eks.amazonaws.com]` → `sts:AssumeRole`
Managed policies:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEKS_CNI_Policy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEC2ContainerRegistryPullOnly`

> Both `ec2` and `eks` principals are trusted because Auto Mode nodes are
> launched by the EKS service, while Standard mode nodes are EC2 instances.

#### KMS Key Policies

**`platformKey`** — grants EKS service access for secret encryption:
```json
{
  "Statement": [
    {"Sid": "Root", "Principal": {"AWS": "arn:aws:iam::<account-id>:root"}, "Action": "kms:*"},
    {"Sid": "EKS", "Principal": {"Service": "eks.amazonaws.com"},
     "Action": ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]}
  ]
}
```

**`databaseKey`** — grants RDS service access for Aurora encryption:
```json
{
  "Statement": [
    {"Sid": "Root", "Principal": {"AWS": "arn:aws:iam::<account-id>:root"}, "Action": "kms:*"},
    {"Sid": "RDS", "Principal": {"Service": "rds.amazonaws.com"},
     "Action": ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey",
                "kms:ReEncryptFrom", "kms:ReEncryptTo"]}
  ]
}
```

**`searchKey`** — grants OpenSearch + ElastiCache service access:
```json
{
  "Statement": [
    {"Sid": "Root", "Principal": {"AWS": "arn:aws:iam::<account-id>:root"}, "Action": "kms:*"},
    {"Sid": "Search", "Principal": {"Service": ["es.amazonaws.com", "elasticache.amazonaws.com"]},
     "Action": ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]}
  ]
}
```

#### Schema Inputs

```yaml
spec:
  # Identity
  name: string | required=true
  namespace: string | default="default"
  region: string | default="us-east-1"
  environment: string | default="dev"
  project: string | default="gen3"
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="delete"

  # Network
  vpcCIDR: string | required=true
  publicSubnetCIDRs: "[]string | required=true"    # exactly 2
  privateSubnetCIDRs: "[]string | required=true"   # exactly 2
  availabilityZones: "[]string | required=true"     # exactly 2

  # Storage
  loggingBucketName: string | required=true
  dataBucketName: string | required=true
  uploadBucketName: string | required=true
  kmsKeyDescription: string | default="Gen3 encryption key"

  # Feature flags (control conditional resource groups)
  databaseEnabled: boolean | default=false
  computeEnabled: boolean | default=false
  searchEnabled: boolean | default=false

  # Database prep inputs (required when databaseEnabled=true)
  dbSubnetCIDRs: "[]string"                        # exactly 2

  # Bridge
  createBridgeSecret: boolean | default=true
```

#### Schema Status (always-present resources only)

```yaml
status:
  vpcID, internetGatewayID, natGatewayID, eipAllocationID
  publicSubnetIDs (×2), privateSubnetIDs (×2)
  publicRouteTableID, privateRouteTableID
  loggingKeyARN, platformKeyARN
  loggingBucketARN, dataBucketARN, uploadBucketARN
```

> Conditional resource outputs (DB SG ID, EKS SG ID, etc.) are NOT in schema
> status — they are exposed via per-capability bridge ConfigMaps. KRO cannot
> reference excluded resources in schema status CEL expressions.

#### Bridge ConfigMap Data Fields

**`foundationBridge`** (always present, 16 fields):
```yaml
data:
  vpc-id: ${vpc.status.?vpcID}
  vpc-cidr: ${schema.spec.vpcCIDR}
  igw-id: ${igw.status.?internetGatewayID}
  eip-allocation-id: ${eip1.status.?allocationID}
  nat-gateway-id: ${natGateway1.status.?natGatewayID}
  public-subnet-1-id: ${publicSubnet1.status.?subnetID}
  public-subnet-2-id: ${publicSubnet2.status.?subnetID}
  private-subnet-1-id: ${privateSubnet1.status.?subnetID}
  private-subnet-2-id: ${privateSubnet2.status.?subnetID}
  public-route-table-id: ${publicRouteTable.status.?routeTableID}
  private-route-table-id: ${privateRouteTable.status.?routeTableID}
  logging-key-arn: ${loggingKey.status.?ackResourceMetadata.?arn}
  platform-key-arn: ${platformKey.status.?ackResourceMetadata.?arn}
  logging-bucket-arn: ${loggingBucket.status.?ackResourceMetadata.?arn}
  data-bucket-arn: ${dataBucket.status.?ackResourceMetadata.?arn}
  upload-bucket-arn: ${uploadBucket.status.?ackResourceMetadata.?arn}
```

**`databasePrepBridge`** (includeWhen: `databaseEnabled`, 6 fields):
```yaml
data:
  db-subnet-1-id: ${dbSubnet1.status.?subnetID}
  db-subnet-2-id: ${dbSubnet2.status.?subnetID}
  db-route-table-id: ${dbRouteTable.status.?routeTableID}
  db-subnet-group-name: ${dbSubnetGroup.spec.name}
  database-key-arn: ${databaseKey.status.?ackResourceMetadata.?arn}
  aurora-sg-id: ${auroraSg.status.?id}
```

**`computePrepBridge`** (includeWhen: `computeEnabled`, 3 fields):
```yaml
data:
  eks-security-group-id: ${eksSecurityGroup.status.?id}
  cluster-role-arn: ${clusterRole.status.?ackResourceMetadata.?arn}
  node-role-arn: ${nodeRole.status.?ackResourceMetadata.?arn}
```

**`searchPrepBridge`** (includeWhen: `searchEnabled`, 2 fields):
```yaml
data:
  search-key-arn: ${searchKey.status.?ackResourceMetadata.?arn}
  opensearch-sg-id: ${openSearchSg.status.?id}
```

**Cost**: ~$37/month base (NAT Gateway + EIP + KMS + minimal S3).
Conditional resources add ~$0 (IAM/SG/subnet/KMS are free or negligible).

---

### Tier 1: Database — `AwsGen3Database1`

**Purpose**: Deploy Aurora PostgreSQL on the pre-built database infrastructure
from Foundation. This tier is thin — it creates ONLY the cluster and instance(s).
All networking, encryption, and security group resources are pre-provisioned by
Tier 0 with `databaseEnabled=true`.

**Prerequisite**: Foundation must have `databaseEnabled=true` so that
`databasePrepBridge` exists. A K8s Secret with the master password must also
exist in the target namespace.

**What it creates** (5–6 resources):

| # | Resource ID | Kind | includeWhen | Purpose |
|---|------------|------|-------------|---------|
| 1 | `spokeNamespace` | Namespace (externalRef) | — | Target namespace |
| 2 | `databasePrepBridge` | ConfigMap (externalRef) | — | Read DB prep outputs from Tier 0 |
| 3 | `auroraCluster` | DBCluster | — | Aurora PostgreSQL Serverless v2 cluster |
| 4 | `auroraInstance1` | DBInstance | — | Primary instance |
| 5 | `auroraInstance2` | DBInstance | `enableReadReplica` | Read replica (HA) |
| 6 | `databaseBridge` | ConfigMap | `createBridgeSecret` | Bridge with Aurora endpoints |

**How Aurora references Tier 0 resources** (via databasePrepBridge):
```yaml
# auroraCluster spec
dbSubnetGroupName: ${databasePrepBridge.data['db-subnet-group-name']}
vpcSecurityGroupIDs:
  - ${databasePrepBridge.data['aurora-sg-id']}
kmsKeyID: ${databasePrepBridge.data['database-key-arn']}
masterUserSecretKMSKeyID: ${databasePrepBridge.data['database-key-arn']}
```

**Aurora cluster spec** (key fields):
```yaml
engine: aurora-postgresql
engineVersion: ${schema.spec.auroraEngineVersion}    # default "16.6"
databaseName: ${schema.spec.auroraDBName}             # default "gen3"
port: 5432
masterUsername: ${schema.spec.auroraMasterUsername}    # default "postgres"
masterUserPassword:
  name: ${schema.spec.masterPasswordSecretName}       # K8s Secret ref (manual prereq)
  key: ${schema.spec.masterPasswordSecretKey}         # default "password"
storageEncrypted: true
serverlessV2ScalingConfiguration:
  minCapacity: ${schema.spec.auroraMinCapacity}       # default "0.5"
  maxCapacity: ${schema.spec.auroraMaxCapacity}       # default "4"
backupRetentionPeriod: 7
enableCloudwatchLogsExports:
  - postgresql
```

> Aurora logging (`enableCloudwatchLogsExports`) is always enabled because the
> field is a static array — no conditional variant needed. If a future
> requirement adds truly different cluster spec shapes, create
> `auroraClusterWithX` / `auroraClusterBasic` resource variants with includeWhen.

**Schema inputs**:
```yaml
spec:
  name: string | required=true
  namespace: string | default="default"
  region: string | default="us-east-1"
  environment: string | default="dev"
  project: string | default="gen3"
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="delete"

  # Bridge references (from Tier 0)
  databasePrepBridgeName: string | required=true
  foundationNamespace: string | required=true

  # Aurora configuration
  auroraEngineVersion: string | default="16.6"
  auroraDBName: string | default="gen3"
  auroraMasterUsername: string | default="postgres"
  masterPasswordSecretName: string | required=true
  masterPasswordSecretKey: string | default="password"
  auroraMinCapacity: string | default="0.5"
  auroraMaxCapacity: string | default="4"

  # Options
  enableReadReplica: boolean | default=false
  createBridgeSecret: boolean | default=true
```

**Schema outputs**:
```yaml
status:
  auroraClusterEndpoint, auroraReaderEndpoint
  auroraClusterARN, auroraInstanceARN
```

**Bridge ConfigMap data** (`databaseBridge`):
```yaml
data:
  aurora-cluster-endpoint: ${auroraCluster.status.?endpoint}
  aurora-reader-endpoint: ${auroraCluster.status.?readerEndpoint}
  aurora-cluster-arn: ${auroraCluster.status.?ackResourceMetadata.?arn}
  aurora-port: "5432"
```

**Cost**: ~$45-350/month (Aurora Serverless v2 scales to near-zero when idle)

---

### Tier 2: Search — `AwsGen3Search1`

**Purpose**: Deploy OpenSearch (ElasticSearch-compatible) for guppy, etl, and
data exploration. This tier is thin — it creates ONLY the OpenSearch domain.
All encryption and security group resources are pre-provisioned by Tier 0
with `searchEnabled=true`.

**Prerequisite**: Foundation must have `searchEnabled=true` so that
`searchPrepBridge` exists. ACK `opensearchservice` controller must be installed.

**What it creates** (4 resources):

| # | Resource ID | Kind | includeWhen | Purpose |
|---|------------|------|-------------|---------|
| 1 | `spokeNamespace` | Namespace (externalRef) | — | Target namespace |
| 2 | `searchPrepBridge` | ConfigMap (externalRef) | — | Read search prep outputs from Tier 0 |
| 3 | `openSearchDomain` | Domain | — | OpenSearch cluster |
| 4 | `searchBridge` | ConfigMap | `createBridgeSecret` | Bridge with OpenSearch endpoint |

**How OpenSearch references Tier 0 resources** (via searchPrepBridge + foundationBridge):
```yaml
# openSearchDomain spec
encryptionAtRestOptions:
  enabled: true
  kmsKeyID: ${searchPrepBridge.data['search-key-arn']}
vpcOptions:
  subnetIDs:
    - ${foundationBridge.data['private-subnet-1-id']}
  securityGroupIDs:
    - ${searchPrepBridge.data['opensearch-sg-id']}
```

**Schema inputs**:
```yaml
spec:
  name: string | required=true
  namespace: string | default="default"
  region: string | default="us-east-1"
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="delete"

  # Bridge references (from Tier 0)
  foundationBridgeName: string | required=true
  searchPrepBridgeName: string | required=true
  foundationNamespace: string | required=true

  # OpenSearch config
  openSearchVersion: string | default="OpenSearch_2.11"
  openSearchInstanceType: string | default="t3.small.search"
  openSearchInstanceCount: integer | default=1
  openSearchVolumeSize: integer | default=20
  openSearchMasterEnabled: boolean | default=false
  createBridgeSecret: boolean | default=true
```

**Schema outputs**:
```yaml
status:
  openSearchEndpoint, openSearchDomainARN
```

**Bridge ConfigMap data** (`searchBridge`):
```yaml
data:
  opensearch-endpoint: ${openSearchDomain.status.?endpoint}
  opensearch-domain-arn: ${openSearchDomain.status.?ackResourceMetadata.?arn}
```

**Cost**: ~$26-50/month (t3.small.search single-node)

**ACK controller required**: `opensearchservice` (not yet installed in gen3-dev)

---

### Tier 3: Compute — `AwsGen3Compute1`

**Purpose**: Deploy EKS cluster and node infrastructure for running Gen3
services. This tier is thin — it creates ONLY the EKS cluster and its
node group (or Auto Mode equivalent). All IAM roles and security groups are
pre-provisioned by Tier 0 with `computeEnabled=true`.

**Prerequisite**: Foundation must have `computeEnabled=true` so that
`computePrepBridge` exists.

**What it creates** (6–8 resources, depending on variant):

#### EKS Standard Mode (`eksAutoMode=false`, default)

| # | Resource ID | Kind | includeWhen | Purpose |
|---|------------|------|-------------|---------|
| 1 | `spokeNamespace` | Namespace (externalRef) | — | Target namespace |
| 2 | `foundationBridge` | ConfigMap (externalRef) | — | VPC, subnets, KMS |
| 3 | `computePrepBridge` | ConfigMap (externalRef) | — | IAM roles, EKS SG |
| 4 | `eksClusterStandard` | Cluster | `!eksAutoMode` | EKS control plane (Standard) |
| 5 | `eksNodeGroup` | Nodegroup | `!eksAutoMode` | Managed node group |
| 6 | `eksAccessEntry` | AccessEntry | `adminRoleARN != ""` | IAM → K8s RBAC mapping |
| 7 | `argoCDClusterSecret` | Secret | `hubClusterName != ""` | Register in hub ArgoCD |
| 8 | `computeBridge` | ConfigMap | `createBridgeSecret` | Bridge with EKS outputs |

#### EKS Auto Mode (`eksAutoMode=true`)

| # | Resource ID | Kind | includeWhen | Purpose |
|---|------------|------|-------------|---------|
| 1–3 | (same externalRefs) | — | — | — |
| 4 | `eksClusterAutoMode` | Cluster | `eksAutoMode` | EKS control plane (Auto Mode) |
| 5 | `eksAccessEntry` | AccessEntry | `adminRoleARN != ""` | IAM → K8s RBAC |
| 6 | `argoCDClusterSecret` | Secret | `hubClusterName != ""` | Register in hub ArgoCD |
| 7 | `computeBridge` | ConfigMap | `createBridgeSecret` | Bridge with EKS outputs |

> No explicit `eksNodeGroup` in Auto Mode — EKS manages nodes automatically
> via `computeConfig.nodePools`.

#### EKS Cluster Variant Details

The two cluster variants exist because EKS Standard and Auto Mode have
**fundamentally different spec shapes** — Auto Mode requires `computeConfig`,
`storageConfig`, and `kubernetesNetworkConfig` blocks that Standard does not use.
KRO cannot conditionally add/remove spec blocks, so separate resources are needed.

**`eksClusterStandard`** (includeWhen: `!eksAutoMode`):
```yaml
name: ${schema.spec.name}-eks
roleARN: ${computePrepBridge.data['cluster-role-arn']}
version: ${schema.spec.kubernetesVersion}
resourcesVPCConfig:
  subnetIDs:
    - ${foundationBridge.data['public-subnet-1-id']}
    - ${foundationBridge.data['public-subnet-2-id']}
    - ${foundationBridge.data['private-subnet-1-id']}
    - ${foundationBridge.data['private-subnet-2-id']}
  securityGroupIDs:
    - ${computePrepBridge.data['eks-security-group-id']}
  endpointPrivateAccess: true
  endpointPublicAccess: true
encryptionConfig:
  - provider:
      keyARN: ${foundationBridge.data['platform-key-arn']}
    resources: [secrets]
accessConfig:
  authenticationMode: "API"
  bootstrapClusterCreatorAdminPermissions: true
logging:
  clusterLogging:
    - types: [api, audit, authenticator, controllerManager, scheduler]
      enabled: true
```

**`eksClusterAutoMode`** (includeWhen: `eksAutoMode`):
```yaml
name: ${schema.spec.name}-eks
roleARN: ${computePrepBridge.data['cluster-role-arn']}
version: ${schema.spec.kubernetesVersion}
resourcesVPCConfig:
  subnetIDs:
    - ${foundationBridge.data['private-subnet-1-id']}
    - ${foundationBridge.data['private-subnet-2-id']}
  securityGroupIDs:
    - ${computePrepBridge.data['eks-security-group-id']}
  endpointPrivateAccess: true
  endpointPublicAccess: true
computeConfig:
  enabled: true
  nodeRoleARN: ${computePrepBridge.data['node-role-arn']}
  nodePools: [system, general-purpose]
storageConfig:
  blockStorage:
    enabled: true
kubernetesNetworkConfig:
  ipFamily: ipv4
  elasticLoadBalancing:
    enabled: true
encryptionConfig:
  - provider:
      keyARN: ${foundationBridge.data['platform-key-arn']}
    resources: [secrets]
accessConfig:
  authenticationMode: "API"
  bootstrapClusterCreatorAdminPermissions: true
logging:
  clusterLogging:
    - types: [api, audit, authenticator, controllerManager, scheduler]
      enabled: true
```

> **Key difference**: Standard uses 4 subnets (public+private) and an explicit
> nodeGroup. Auto Mode uses 2 private subnets only and manages nodes via
> `computeConfig.nodePools`. Auto Mode also enables `storageConfig.blockStorage`
> and `kubernetesNetworkConfig.elasticLoadBalancing`.

**Schema inputs**:
```yaml
spec:
  name: string | required=true
  namespace: string | default="default"
  region: string | default="us-east-1"
  environment: string | default="dev"
  project: string | default="gen3"
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="delete"

  # Bridge references (from Tier 0)
  foundationBridgeName: string | required=true
  computePrepBridgeName: string | required=true
  foundationNamespace: string | required=true

  # EKS configuration
  kubernetesVersion: string | default="1.31"
  eksAutoMode: boolean | default=false

  # Standard mode node group config (ignored if eksAutoMode=true)
  nodeInstanceTypes: "[]string | required=true"
  nodeDesiredSize: integer | default=2
  nodeMinSize: integer | default=1
  nodeMaxSize: integer | default=4
  nodeDiskSize: integer | default=20
  nodeAMIType: string | default="AL2023_x86_64_STANDARD"

  # Access (optional)
  adminRoleARN: string | default=""
  hubClusterName: string | default=""
  argoCDNamespace: string | default="argocd"

  # Bridge
  createBridgeSecret: boolean | default=true
```

**Schema outputs**:
```yaml
status:
  eksClusterARN, eksClusterEndpoint, eksClusterName
  eksClusterCA (certificateAuthority.data)
```

> `eksSecurityGroupID`, `clusterRoleARN`, `nodeRoleARN` are NOT in Tier 3
> status — they are in the `computePrepBridge` from Tier 0.

**Bridge ConfigMap data** (`computeBridge`):
```yaml
data:
  eks-cluster-arn: ${eksClusterStandard.status.?ackResourceMetadata.?arn.orValue(
                     eksClusterAutoMode.status.?ackResourceMetadata.?arn.orValue("loading"))}
  eks-cluster-endpoint: ${eksClusterStandard.status.?endpoint.orValue(
                          eksClusterAutoMode.status.?endpoint.orValue("loading"))}
  eks-cluster-name: ${schema.spec.name}-eks
  eks-cluster-ca: ${eksClusterStandard.status.?certificateAuthority.?data.orValue(
                    eksClusterAutoMode.status.?certificateAuthority.?data.orValue("loading"))}
```

> The bridge uses chained `orValue()` to reference whichever cluster variant
> was created. Since the variants are mutually exclusive (`eksAutoMode` is a
> boolean), exactly one will exist. The excluded variant's references evaluate
> to nil, and `orValue()` falls through to the other. This pattern requires
> validation — if KRO does not support cross-variant `orValue()` chaining,
> use two conditional bridge ConfigMaps instead (`computeBridgeStandard` and
> `computeBridgeAutoMode`).

**Cost**: ~$350/month (EKS $72 + 2× m5.xlarge $280 for Standard mode)

---

### Tier 4: Application IAM — `AwsGen3AppIAM1`

**Purpose**: Per-service IRSA roles, SQS queues, and Secrets Manager secrets needed by Gen3 application services.

**What it creates** (12-20 resources, conditional):
| # | Resource ID | Kind | Condition | Purpose |
|---|------------|------|-----------|---------|
| 1 | `fenceRole` | IAM Role | `fenceEnabled` | Fence IRSA (SQS send, S3 access) |
| 2 | `auditRole` | IAM Role | `auditEnabled` | Audit IRSA (SQS receive) |
| 3 | `hatcheryRole` | IAM Role | `hatcheryEnabled` | Hatchery IRSA (EC2, STS) |
| 4 | `manifestserviceRole` | IAM Role | `manifestserviceEnabled` | Manifest S3 IRSA |
| 5 | `albControllerRole` | IAM Role | `albEnabled` | ALB controller IRSA |
| 6 | `externalSecretsRole` | IAM Role | `externalSecretsEnabled` | Secrets Manager IRSA |
| 7 | `auditQueue` | SQS Queue | `auditEnabled` | Audit event pipeline |
| 8 | `ssjdispatcherQueue` | SQS Queue | `ssjdispatcherEnabled` | S3→indexd auto-index |
| 9 | `manifestBucket` | S3 Bucket | `manifestserviceEnabled` | Workspace manifests |
| 10 | `fenceConfigSecret` | SM Secret | `fenceEnabled` | Fence YAML config |
| 11 | `fenceJwtKeysSecret` | SM Secret | `fenceEnabled` | Fence RSA keys |
| 12 | `esProxyCredsSecret` | SM Secret | `openSearchEnabled` | OpenSearch IAM creds |

**Schema inputs**:
```yaml
spec:
  name: string | required=true
  region: string | default="us-east-1"
  adoptionPolicy: string | default="adopt-or-create"
  deletionPolicy: string | default="delete"

  # EKS reference (for IRSA trust policies)
  eksClusterOIDCProvider: string | required=true
  spokeNamespace: string | required=true

  # Data bucket references (from Foundation)
  dataBucketARN: string | required=true
  uploadBucketARN: string | required=true

  # Feature flags
  fenceEnabled: boolean | default=true
  auditEnabled: boolean | default=true
  hatcheryEnabled: boolean | default=true
  manifestserviceEnabled: boolean | default=true
  albEnabled: boolean | default=true
  externalSecretsEnabled: boolean | default=false
  ssjdispatcherEnabled: boolean | default=false
  openSearchEnabled: boolean | default=false
```

**Schema outputs**:
```yaml
status:
  fenceRoleARN, auditRoleARN, hatcheryRoleARN
  manifestserviceRoleARN, albControllerRoleARN
  auditQueueURL, ssjdispatcherQueueURL
  manifestBucketARN
```

**Cost**: ~$5/month (mostly IAM/SQS = free tier, only manifest bucket has cost)

**ACK controllers required**: `sqs` (needs to be added), `sns` (optional)

---

### Tier 5: Application — gen3-helm (Helm-deployed)

**Purpose**: Deploy Gen3 application services on the EKS cluster. This is NOT
an RGD — it is a Helm chart deployment managed by ArgoCD.

**Deployment method**: ArgoCD Application targeting gen3-helm umbrella chart.
Deployed via the fleet ApplicationSet on the hub cluster (gen3-kro pattern)
or directly via an ArgoCD Application in gen3-dev.

**What it deploys** (14 core + 23 optional services):

| # | Service | Required? | Database | AWS Dependencies | Role |
|---|---------|-----------|----------|-----------------|------|
| 1 | **fence** | Yes | `fence` (Aurora) | S3, SQS, Secrets Mgr | Authentication |
| 2 | **arborist** | Yes | `arborist` (Aurora) | — | Authorization |
| 3 | **indexd** | Yes | `indexd` (Aurora) | — | Data indexing |
| 4 | **sheepdog** | Yes | `sheepdog` (Aurora) | — | Data submission |
| 5 | **peregrine** | Yes | shares sheepdog | — | Data query |
| 6 | **portal** | Yes | — | — | Web UI |
| 7 | **revproxy** | Yes | — | ACM cert ARN | Reverse proxy |
| 8 | **metadata** | Yes | `metadata` (Aurora) | — | Metadata API |
| 9 | **audit** | Yes | `audit` (Aurora) | SQS (read) | Audit logging |
| 10 | **hatchery** | Yes | — | EC2, STS | Workspaces |
| 11 | **ambassador** | Yes | — | — | Workspace proxy |
| 12 | **manifestservice** | Yes | — | S3 (IRSA) | Workspace files |
| 13 | **wts** | Yes | `wts` (Aurora) | — | Workspace tokens |
| 14 | **etl** | Yes | reads sheepdog DB | ES/OpenSearch | Data transform |
| 15 | guppy | Optional | — | ES/OpenSearch | Explorer page |
| 16 | aws-es-proxy | Optional | — | OpenSearch | ES proxy |
| 17 | ssjdispatcher | Optional | — | SQS, S3 | Upload indexing |
| 18 | requestor | Optional | `requestor` (Aurora) | — | Access requests |
| 19 | sower | Optional | — | — | Job dispatch |
| 20 | argo-wrapper | Optional | `argo` (Aurora) | — | Workflows |
| 21 | dashboard | Optional | — | S3 | Analytics |
| 22+ | frontend-framework, cedar, cohort-middleware, etc. | Optional | varies | varies | Extended features |

**Schema inputs** (ArgoCD Application/ApplicationSet parameters):
```yaml
# Global settings (from ArgoCD parameters or values file)
global:
  hostname: string          # Commons URL
  environment: string       # Environment name
  dev: boolean              # true = in-cluster DBs, false = external Aurora
  aws:
    enabled: boolean        # AWS-specific ingress + annotations
    region: string          # AWS region
  revproxyArn: string       # ACM certificate ARN
  postgres:
    master:
      host: string          # Aurora writer endpoint (from Database bridge)
      port: string          # "5432"
      username: string      # Master username
      password: string      # Master password (from K8s Secret)
  externalSecrets:
    deploy: boolean         # Use ExternalSecret CRs
```

**Infrastructure inputs consumed** (from bridge ConfigMaps):

| Input | Source Tier | Bridge Key |
|-------|-----------|------------|
| Aurora writer endpoint | Tier 1 (Database) | `aurora-cluster-endpoint` |
| Aurora port | Tier 1 (Database) | `aurora-port` |
| S3 data bucket name | Tier 0 (Foundation) | `data-bucket-arn` |
| S3 upload bucket name | Tier 0 (Foundation) | `upload-bucket-arn` |
| OpenSearch endpoint | Tier 2 (Search) | `opensearch-endpoint` |
| IRSA role ARNs | Tier 4 (App IAM) | `fence-role-arn`, etc. |
| SQS queue URLs | Tier 4 (App IAM) | `audit-queue-url` |
| ACM cert ARN | External (not RGD) | Manual or SSM parameter |

**Dependencies**: Tier 1 (Database), Tier 3 (Compute), Tier 4 (Application IAM).
Optional: Tier 2 (Search) for guppy/etl with managed OpenSearch.

**Cost**: ~$0 incremental (pods run on existing EKS nodes from Tier 3)

---

### Tier 6: Observability — LGTM Stack (Helm-deployed)

**Purpose**: Deploy the Grafana LGTM observability stack on the EKS cluster
for application and infrastructure monitoring. This is NOT an RGD —
it is a set of Helm chart deployments managed by ArgoCD.

**Deployment method**: Separate ArgoCD Applications for each component.

**What it deploys**:

| # | Component | Helm Chart | Purpose | AWS Dependencies |
|---|-----------|-----------|---------|------------------|
| 1 | **Grafana** | lgtm-distributed | Dashboards, visualization | — |
| 2 | **Loki** | lgtm-distributed | Log aggregation | S3 (IRSA) |
| 3 | **Mimir** | lgtm-distributed | Long-term metrics (Prometheus) | S3 (IRSA) |
| 4 | **Tempo** | lgtm-distributed | Distributed tracing (optional) | — |
| 5 | **Alloy** | grafana/alloy | Telemetry collector | — |
| 6 | **Faro Collector** | faro-collector | Frontend browser observability | — |

**Infrastructure inputs consumed**:

| Input | Source Tier | Bridge Key |
|-------|-----------|------------|
| Observability S3 bucket | Tier 7 or Tier 0 | `observability-bucket-arn` |
| IRSA role for Loki/Mimir | Tier 4 (App IAM) | `observability-role-arn` |

**Dependencies**: Tier 3 (Compute — needs EKS). Optional: Tier 4 (IRSA for S3).

**Cost**: ~$5-15/month (CloudWatch Logs ingestion if forwarding, S3 storage for Mimir/Loki)

---

### Tier 7: Advanced & Monitoring — `AwsGen3Advanced1`

**Purpose**: Optional advanced infrastructure for production hardening and
AWS-native monitoring. Combines the old Tier 5 (Advanced) and Tier 6
(Monitoring) into a single optional RGD. All resources are conditional.

**What it creates** (conditional, 0-24 resources):

#### Advanced Infrastructure

| # | Resource ID | Kind | Condition | Purpose |
|---|------------|------|-----------|---------|
| 1 | `wafWebACL` | WAFv2 WebACL | `wafEnabled` | Web Application Firewall |
| 2 | `cognitoUserPool` | Cognito UserPool | `cognitoEnabled` | Managed auth |
| 3 | `cognitoClient` | Cognito UserPoolClient | `cognitoEnabled` | OAuth client |
| 4 | `efsFileSystem` | EFS FileSystem | `efsEnabled` | Shared storage |
| 5 | `efsMountTarget1` | EFS MountTarget | `efsEnabled` | EFS AZ-a access |
| 6 | `efsMountTarget2` | EFS MountTarget | `efsEnabled` | EFS AZ-b access |
| 7 | `cacheSubnetGroup` | ElastiCache SubnetGroup | `cacheEnabled` | Redis placement |
| 8 | `cacheCluster` | ElastiCache Cluster | `cacheEnabled` | Redis/session cache |
| 9 | `dashboardBucket` | S3 Bucket | `dashboardEnabled` | Analytics data |
| 10 | `observabilityBucket` | S3 Bucket | `observabilityEnabled` | Grafana/Loki/Mimir S3 backend |

#### CloudWatch Monitoring

| # | Resource ID | Kind | Condition | Purpose |
|---|------------|------|-----------|---------|
| 11 | `logGroupVPC` | CW LogGroup | `monitoringEnabled` | VPC Flow Logs storage |
| 12 | `logGroupEKS` | CW LogGroup | `eksEnabled` | EKS control plane logs |
| 13 | `logGroupApp` | CW LogGroup | `appLogsEnabled` | Gen3 application logs |
| 14 | `vpcFlowLog` | EC2 FlowLog | `monitoringEnabled` | VPC network traffic capture |
| 15 | `alarmAuroraCP` | CW Alarm | `auroraEnabled` | Aurora CPU > 80% |
| 16 | `alarmAuroraConn` | CW Alarm | `auroraEnabled` | Aurora connections > threshold |
| 17 | `alarmAuroraStorage` | CW Alarm | `auroraEnabled` | Aurora storage space low |
| 18 | `alarmEKSAPIErrors` | CW Alarm | `eksEnabled` | EKS API server 5xx rate |
| 19 | `alarmEKSNodeNotReady` | CW Alarm | `eksEnabled` | Node NotReady condition |
| 20 | `alarmNATErrors` | CW Alarm | `natEnabled` | NAT Gateway errors |
| 21 | `alarmS3Errors` | CW Alarm | `monitoringEnabled` | Data bucket 4xx/5xx rate |
| 22 | `snsTopic` | SNS Topic | `snsEnabled` | Alert notification target |
| 23 | `snsSubscription` | SNS Subscription | `snsEnabled` | Email/Slack/PagerDuty endpoint |
| 24 | `advancedBridge` | ConfigMap | `createBridgeSecret` | Bridge ConfigMap w/ alarm ARNs |

**ACK controllers required**: `wafv2`, `efs`, `elasticache`, `cloudwatchlogs`, `sns`
(Cognito has no ACK chart — may need alternative approach)

**Cost**: Variable ($0-200/month depending on features enabled)

---

## 4. Deployment Profiles

Each profile controls Foundation feature flags (`databaseEnabled`, `computeEnabled`,
`searchEnabled`) and which downstream tier instances to deploy. Since all prep
infrastructure lives in Foundation, the feature flags determine what the Foundation
pre-provisions — and downstream tiers are deployed only when their prep resources exist.

### 4.1 Profile Definitions

| Profile | Foundation Flags | Downstream Tiers | App Tiers | Est. Cost | Use Case |
|---------|-----------------|-------------------|-----------|-----------|----------|
| **minimal-dev** | all false | — | — | ~$37/mo | Validate networking/storage — cheapest |
| **dev** | all false | — | Tier 5 (dev mode) | ~$37/mo | Dev environment, in-cluster PG+ES on Kind/Docker |
| **database-only** | `databaseEnabled` | Tier 1 | — | ~$80/mo | Validate Aurora independently |
| **staging** | all true | Tier 1 + 2 + 3 + 4 | Tier 5 + 6 | ~$500/mo | Full Gen3 with managed services |
| **production** | all true | Tier 1 + 2 + 3 + 4 + 7 | Tier 5 + 6 | ~$700-900/mo | Production with monitoring |

### 4.2 Profile Switch Matrix

**Tier 0 Foundation flags** determine which prep resources are created:

| Flag | minimal-dev | dev | database-only | staging | production |
|------|-------------|-----|---------------|---------|------------|
| `databaseEnabled` (T0) | false | false | true | true | true |
| `computeEnabled` (T0) | false | false | false | true | true |
| `searchEnabled` (T0) | false | false | false | true | true |

**Downstream tier deployment** (deploy only if Foundation flag enabled):

| Tier | minimal-dev | dev | database-only | staging | production |
|------|-------------|-----|---------------|---------|------------|
| Tier 1 Database | — | — | deploy | deploy | deploy |
| Tier 2 Search | — | — | — | deploy | deploy |
| Tier 3 Compute | — | — | — | deploy | deploy |
| Tier 4 App IAM | — | — | — | deploy | deploy |
| Tier 7 Advanced | — | — | — | — | deploy |

**Downstream tier options** (per-tier instance config):

| Switch | Tier | Default | Purpose |
|--------|------|---------|---------|
| `enableReadReplica` | T1 | false | Aurora HA (adds ~$45-175/mo) |
| `eksAutoMode` | T3 | false | Auto Mode vs Standard |
| `wafEnabled` | T7 | false | Web Application Firewall |
| `cacheEnabled` | T7 | false | ElastiCache Redis |
| `monitoringEnabled` | T7 | false | CloudWatch alarms |

**Application tiers** (independent of infrastructure):

| Switch | minimal-dev | dev | database-only | staging | production |
|--------|-------------|-----|---------------|---------|------------|
| gen3-helm (T5) | — | dev mode | — | production | production |
| LGTM (T6) | — | — | — | deploy | deploy |

### 4.3 Application Deployment (With/Without App)

Each profile can deploy **infrastructure-only** or **infrastructure + application**.
The application layer has two deployment paths:

**Path A — gen3-helm via ArgoCD (Tier 5)**
The gen3-helm umbrella chart is deployed as an ArgoCD Application, NOT via RGDs.
Infrastructure outputs flow to the application via bridge ConfigMaps:

1. **Infrastructure RGDs** create AWS resources + expose outputs via bridge ConfigMaps
2. **ArgoCD Application** for gen3-helm reads infrastructure outputs and maps them
   to Helm values (`global.postgres.host`, `global.es.endpoint`, etc.)
3. **Dev mode** (`global.dev: true`) skips external infrastructure — uses in-cluster
   PostgreSQL and Elasticsearch. Only needs Foundation (Tier 0) for networking.

```
Infrastructure (RGDs)  →  Bridge ConfigMaps  →  ArgoCD Application  →  gen3-helm
```

**Path B — Observability LGTM stack (Tier 6)**
The LGTM stack (Grafana, Loki, Mimir, Tempo, Alloy, Faro) is deployed as
separate Helm charts via ArgoCD, independent of gen3-helm.

**Bridge ConfigMap placement:** Foundation always creates `foundationBridge`.
Conditional bridges (`databasePrepBridge`, `computePrepBridge`, `searchPrepBridge`)
are created only when the corresponding flag is true. Downstream tiers create
their own output bridges (`databaseBridge`, `computeBridge`, `searchBridge`).
The application layer reads from whichever bridges exist:
- **dev profile**: Tier 5 reads `foundationBridge` only — uses `global.dev: true`
- **staging/production**: Tier 5 reads `foundationBridge` + `databaseBridge` +
  `computeBridge` + (optionally) `searchBridge`

---

## 5. Cross-Tier Data Flow & Bridge Pattern

### 5.1 Bridge ConfigMap Pattern

KRO RGDs are isolated — no cross-graph imports. Data flows between tiers using
**bridge ConfigMaps**:

1. **Source tier** creates a K8s ConfigMap with all outputs in `data`
2. **Consuming tier** uses `externalRef` to read that ConfigMap cross-namespace
3. Template CEL expressions reference the ConfigMap's data fields using bracket notation

**Foundation creates up to 4 bridge ConfigMaps** — one always-present, three conditional:

```yaml
# Always-present: foundationBridge
- id: foundationBridge
  includeWhen:
    - ${schema.spec.createBridgeSecret == true}
  readyWhen:
    - ${foundationBridge.metadata.?name.orValue('null') != 'null'}
  template:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.name}-foundation-bridge
      namespace: ${spokeNamespace.metadata.name}
      labels:
        gen3.io/tier: foundation
        gen3.io/bridge: "true"
    data:
      vpc-id: ${vpc.status.?vpcID.orValue("loading")}
      private-subnet-1-id: ${privateSubnet1.status.?subnetID.orValue("loading")}
      # ...16 fields total (see Tier 0 definition)

# Conditional: databasePrepBridge (only when databaseEnabled=true)
- id: databasePrepBridge
  includeWhen:
    - ${schema.spec.databaseEnabled == true}
    - ${schema.spec.createBridgeSecret == true}
  template:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.name}-database-prep-bridge
      namespace: ${spokeNamespace.metadata.name}
      labels:
        gen3.io/tier: foundation
        gen3.io/bridge: "true"
        gen3.io/capability: database
    data:
      db-subnet-1-id: ${dbSubnet1.status.?subnetID.orValue("loading")}
      # ...6 fields total
```

```yaml
# In Tier 1 (reads BOTH bridges — Foundation + Database Prep):
- id: foundationBridge
  externalRef:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.foundationBridgeName}
      namespace: ${schema.spec.foundationNamespace}

- id: databasePrepBridge
  externalRef:
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ${schema.spec.databasePrepBridgeName}
      namespace: ${schema.spec.foundationNamespace}

# Then in the auroraCluster template:
dbSubnetGroupName: ${databasePrepBridge.data['db-subnet-group-name']}
vpcSecurityGroupIDs:
  - ${databasePrepBridge.data['aurora-sg-id']}
kmsKeyID: ${databasePrepBridge.data['database-key-arn']}
```

**Bridge key naming**: kebab-case (`vpc-id`, `nat-gateway-id`, `platform-key-arn`).
**Access in templates**: `${foundationBridge.data['vpc-id']}` (bracket notation for
hyphenated keys).

### 5.2 Bridge Inventory

| Bridge | Created By | Scope | includeWhen | Fields | Consumers |
|--------|-----------|-------|-------------|--------|-----------|
| `foundationBridge` | Tier 0 | Always present | `createBridgeSecret` | 16 | T1, T2, T3, T4, T5, T6, T7 |
| `databasePrepBridge` | Tier 0 | DB prep outputs | `databaseEnabled` | 6 | T1 |
| `computePrepBridge` | Tier 0 | Compute prep outputs | `computeEnabled` | 3 | T3 |
| `searchPrepBridge` | Tier 0 | Search prep outputs | `searchEnabled` | 2 | T2 |
| `databaseBridge` | Tier 1 | Aurora outputs | `createBridgeSecret` | 4 | T4, T5 |
| `computeBridge` | Tier 3 | EKS outputs | `createBridgeSecret` | 4 | T4, T5, T6 |
| `searchBridge` | Tier 2 | OpenSearch outputs | `createBridgeSecret` | 2 | T5 |

### 5.3 Data Flow Diagram

```
                        INFRASTRUCTURE RGD TIERS
                        ========================

Tier 0 (Foundation) — AwsGen3Foundation1
  creates: VPC, subnets, IGW, NAT, KMS keys, S3 buckets
  feature flags: databaseEnabled, computeEnabled, searchEnabled
  conditional: DB subnets/SG/KMS, EKS SG/IAM, Search SG/KMS
  bridges:
    ├── foundationBridge (always, 16 fields)
    ├── databasePrepBridge (databaseEnabled, 6 fields)
    ├── computePrepBridge (computeEnabled, 3 fields)
    └── searchPrepBridge (searchEnabled, 2 fields)
      │
      ├──────── databasePrepBridge ──┬─── computePrepBridge ──┬── searchPrepBridge
      │         + foundationBridge   │    + foundationBridge   │   + foundationBridge
      ▼                              ▼                         ▼
Tier 1 (Database)              Tier 3 (Compute)          Tier 2 (Search)
  AwsGen3Database1               AwsGen3Compute1           AwsGen3Search1
  creates: Aurora cluster        creates: EKS cluster      creates: OpenSearch
  + instance(s)                  + node group OR Auto       domain
  bridge: databaseBridge         bridge: computeBridge      bridge: searchBridge
  (4 fields)                     (4 fields)                 (2 fields)
      │                              │
      │    ┌─────────────────────────┘
      ▼    ▼
Tier 4 (Application IAM) — AwsGen3AppIAM1
  reads: foundationBridge + databaseBridge + computeBridge
  creates: IRSA roles, SQS queues, Secrets Manager entries

                        APPLICATION HELM TIERS
                        ======================

Tier 5 (Application — gen3-helm)
  reads: foundationBridge + databaseBridge + computeBridge + searchBridge
  deploys: Gen3 services (fence, indexd, sheepdog, portal, etc.)
  mode: dev (in-cluster PG+ES) or production (external Aurora+OS)

Tier 6 (Observability — LGTM)
  reads: foundationBridge + computeBridge
  deploys: Grafana, Loki, Mimir, Tempo, Alloy, Faro
```

### 5.4 Route Tables & Security Groups in RGDs — Critical Analysis

**Route Tables**: Routes are defined **inline** in the RouteTable spec, not as
separate `Route` resources. This is how ACK's EC2 controller works — the
`routes` field is an array within the RouteTable spec.

```yaml
# ✅ CORRECT: Routes inline in RouteTable
- id: publicRouteTable
  template:
    spec:
      vpcID: ${vpc.status.?vpcID}
      routes:
        - destinationCIDRBlock: "0.0.0.0/0"
          gatewayID: ${igw.status.?internetGatewayID}
      tags:
        - key: Name
          value: ${schema.spec.name}-public-rt

# ❌ WRONG: No separate Route resource in ACK EC2 controller
```

**Security Groups**: Rules are defined **inline** in the SecurityGroup spec via
`ingressRules` and `egressRules` arrays.

```yaml
# ✅ CORRECT: Rules inline in SecurityGroup
- id: eksSecurityGroup
  template:
    spec:
      description: "EKS cluster security group"
      name: ${schema.spec.name}-eks-sg
      vpcID: ${vpc.status.?vpcID}
      ingressRules:
        - ipProtocol: tcp
          fromPort: 443
          toPort: 443
          ipRanges:
            - cidrIP: ${schema.spec.vpcCIDR}
              description: "Allow API server access from VPC"
        - ipProtocol: tcp
          fromPort: 10250
          toPort: 10250
          ipRanges:
            - cidrIP: ${schema.spec.vpcCIDR}
              description: "Allow kubelet access from VPC"
```

**Dynamic Route/SG entries from arrays**: NOT supported by KRO. Routes and rules
must be statically defined. For varying numbers of routes:
- **Option A**: Hardcode the common routes (usually 1-3 routes per RT)
- **Option B**: Use `includeWhen` for optional routes (e.g., VPC peering route)
- **Option C**: Use multiple RouteTable resources for different route sets

This is acceptable because:
- Public RT: always has exactly 1 route (0.0.0.0/0 → IGW)
- Private RT: always has exactly 1 route (0.0.0.0/0 → NAT)
- DB RT: always has exactly 1 route (0.0.0.0/0 → NAT)
- Security groups: rules are well-defined per service (EKS: 443+10250, Aurora: 5432)

**Subnet association with route tables**: In ACK's EC2 controller, subnets are
associated with route tables via the `routeTableAssociations` field on the Subnet,
or via separate RouteTableAssociation resources. Gen3-kro uses `routeTableID` on
the Subnet spec to associate them.

### 5.5 KRO forEach for Subnets

KRO supports `forEach` for creating multiple resources from array inputs:
```yaml
- id: privateSubnets
  forEach:
    - cidr: "${schema.spec.privateSubnetCIDRs}"
  template:
    apiVersion: ec2.services.k8s.aws/v1alpha1
    kind: Subnet
    metadata:
      name: ${schema.spec.name}-private-${cidr}
    spec:
      cidrBlock: ${cidr}
      vpcID: ${vpc.status.?vpcID}
```

**However**: gen3-kro does NOT use forEach — it uses hardcoded subnet1/subnet2.
This is because:
1. Status references need specific IDs (`${privateSubnet1.status.?subnetID}`)
2. ForEach resources produce collections, not individually addressable resources
3. Downstream resources (NAT, route table associations) need specific subnet references

**Recommendation**: Continue using hardcoded subnets (2 per type). Test forEach
with the KRO capability test RGDs before considering for production use.

---

## 6. Optional Resources Within Each Tier

### Tier 0 — Foundation
| Resource Group | Optional? | Condition | Justification |
|---------------|-----------|-----------|---------------|
| Database prep (7 resources) | Yes | `databaseEnabled` | DB subnets, SG, KMS, bridge — only if deploying Aurora |
| Compute prep (4 resources) | Yes | `computeEnabled` | IAM roles, EKS SG, bridge — only if deploying EKS |
| Search prep (3 resources) | Yes | `searchEnabled` | KMS, OpenSearch SG, bridge — only if deploying OpenSearch |
| NAT Gateway + EIP | Always-on | — | Required for private subnet egress. Could be deferred if VPC endpoints used. |
| Upload Bucket | Always-on | — | Always created. Could be made conditional in future Foundation v3. |

### Tier 1 — Database
| Resource | Optional? | Condition | Justification |
|----------|-----------|-----------|---------------|
| Aurora Read Replica | Yes | `enableReadReplica` | HA only — adds ~$45-175/mo |
| Database Bridge | Recommended | `createBridgeSecret` | Needed if any downstream tier consumes Aurora outputs |

### Tier 2 — Search
| Resource | Optional? | Condition | Justification |
|----------|-----------|-----------|---------------|
| Entire tier | Yes | — | Not needed if running ES in-cluster (`global.dev=true`) |
| Multi-AZ | Config | `openSearchInstanceCount > 1` | HA, adds cost |
| Dedicated master | Config | `openSearchMasterEnabled` | Only for 3+ nodes |

### Tier 3 — Compute
| Resource | Optional? | Condition | Justification |
|----------|-----------|-----------|---------------|
| EKS Node Group | Variant | `!eksAutoMode` | Only in Standard mode (Auto Mode manages nodes) |
| EKS Access Entry | Yes | `adminRoleARN != ""` | Only if IAM admin access needed |
| ArgoCD Cluster Secret | Yes | `hubClusterName != ""` | Only for hub-spoke pattern |

### Tier 4 — Application IAM
All resources are individually conditional via `*Enabled` flags. Full list:
| Flag | Resources Created | Default |
|------|-------------------|---------|
| `fenceEnabled` | fenceRole, fenceConfigSecret, fenceJwtSecret | true |
| `auditEnabled` | auditRole, auditQueue | true |
| `hatcheryEnabled` | hatcheryRole | true |
| `manifestserviceEnabled` | manifestserviceRole, manifestBucket | true |
| `albEnabled` | albControllerRole | true |
| `externalSecretsEnabled` | externalSecretsRole | false |
| `ssjdispatcherEnabled` | ssjdispatcherQueue | false |

### Tier 5 — Application (gen3-helm)
All services are individually conditional via `enabled` flags in the gen3-helm values.
See Tier 5 definition (Section 3) for the full 22-service table.

### Tier 6 — Observability (LGTM)
All components are individually conditional via separate Helm chart installations.
See Tier 6 definition (Section 3) for the full component table.

### Tier 7 — Advanced & Monitoring
Everything is optional. Each feature has its own enable flag. See Tier 7
definition (Section 3) for the combined 24-resource table.

---

## 7. Existing RGDs → Migration Path

### What to keep
| Current RGD | Status | Disposition | Reason |
|-------------|--------|-------------|--------|
| `AwsGen3Infra1Flat` | Reference | **Keep as-is** | Full monolithic graph from gen3-kro. Not for modular use. |
| `AwsGen3Test1Flat` | Deployed | **Keep as-is** | Proven test graph (~$37/mo, 28 real AWS resources). Integration test target. |
| `AwsGen3Foundation1` | ✅ Built | **Revised** | Foundation-heavy, 31 resources with feature flags. |

### What was built (modular)
| New RGD | Replaces | Key Changes |
|---------|----------|-------------|
| `AwsGen3Foundation1` | Foundation1 (extends) | 31 resources (16 always + 15 conditional). Feature flags: `databaseEnabled`, `computeEnabled`, `searchEnabled`. 4 bridge ConfigMaps. |
| `AwsGen3Database1` | Database1 | Thin: 5-6 resources (Aurora only). Reads `databasePrepBridge` from Foundation1. |
| `AwsGen3Compute1` | Compute1 | Thin: 6-8 resources (EKS only). Standard/Auto Mode variants. Reads `computePrepBridge` from Foundation1. |
| `AwsGen3Search1` | — (new) | Thin: 4 resources (OpenSearch only). Reads `searchPrepBridge` from Foundation1. |

### Monolithic RGDs (reference only)
| RGD | Status | Notes |
|-----|--------|-------|
| `AwsGen3Base1Flat` | Reference | Mixed network + storage scope — Foundation1 covers this properly. |
| `AwsGen3Network1Flat` | Reference | Creates DB infrastructure, not generic networking — Database1 covers this. |
| `AwsGen3Infra1Flat` | Reference | Monolithic — modular tiers 0-3 cover this. |

### Build phases
1. **Phase 1 — KRO Capability Tests** ✅ Complete: 8 test RGDs validated forEach,
   includeWhen, externalRef, bridge ConfigMap, CEL expressions, SG conditional,
   cross-RGD status flow. Results documented in Plan 03.
2. **Phase 2 — Foundation v1** ✅ Complete: `AwsGen3Foundation1` (17 resources).
3. **Phase 3 — Database v1** ✅ Complete: `AwsGen3Database1` (11 resources, DB prep + Aurora).
4. **Phase 4 — Compute v1** ✅ Complete: `AwsGen3Compute1` (8 resources, IAM + SG + EKS).
5. **Phase 5 — Foundation (revised)**: Build `AwsGen3Foundation1` (31 resources).
   Add `databaseEnabled`, `computeEnabled`, `searchEnabled` flags.
   Add per-capability bridge ConfigMaps.
6. **Phase 6 — Database (revised)**: Build `AwsGen3Database1` (thin, Aurora only).
   Reads `databasePrepBridge` + `foundationBridge`.
7. **Phase 7 — Compute (revised)**: Build `AwsGen3Compute1` (thin, EKS only).
   Standard + Auto Mode variants. Reads `computePrepBridge` + `foundationBridge`.
8. **Phase 8 — Search**: Build `AwsGen3Search1` (thin, OpenSearch only).
   Needs `opensearchservice` ACK controller.
9. **Phase 9 — Application IAM**: Build `AwsGen3AppIAM1`. Needs `sqs` ACK controller.
10. **Phase 10 — Application**: Configure gen3-helm ArgoCD Application (Tier 5).
11. **Phase 11 — Observability**: Configure LGTM Helm charts (Tier 6).
12. **Phase 12 — Advanced & Monitoring**: Build `AwsGen3Advanced1` (Tier 7).

> **AwsGen3Test1Flat** remains available throughout. It is NOT retired — it continues as the
> integration test graph for validating the KRO + ACK pipeline on real AWS resources.
> Its 28-resource scope (all prep infra, no managed services) served as the blueprint
> for the Foundation1 design.

---

## 8. New ACK Controllers Needed

| Tier | Controller | Chart | Purpose | Status |
|------|-----------|-------|---------|--------|
| Tier 2 | opensearchservice | `opensearchservice-chart` | OpenSearch domains | Not installed |
| Tier 4 | sqs | `sqs-chart` | SQS queues | Not installed |
| Tier 7 | wafv2 | `wafv2-chart` | WAF Web ACLs | Not installed |
| Tier 7 | elasticache | `elasticache-chart` | Redis clusters | Not installed |
| Tier 7 | efs | `efs-chart` | EFS file systems | Not installed |
| Tier 7 | cloudwatchlogs | `cloudwatchlogs-chart` | CloudWatch log groups | Not installed |
| Tier 7 | sns | `sns-chart` | SNS topics and subscriptions | Not installed |
| Tier 7 | cognito-idp | — | Cognito (no ACK chart yet) | N/A |

**Already installed (Tiers 0, 1, 3)**: ec2, eks, iam, kms, rds, s3, secretsmanager.
**Next to add**: `opensearchservice` (Tier 2) and `sqs` (Tier 4).

---

## 9. Implementation Priority

| Priority | Task | Status | Effort | Reason |
|----------|------|--------|--------|--------|
| **P0** | KRO Capability Test RGDs | ✅ Done | Low | 8 tests validated — forEach, includeWhen, bridge, CEL, SG conditional, cross-RGD |
| **P1** | `AwsGen3Foundation1` (v1) | ✅ Done | Medium | 17 resources, bridge ConfigMap with 16 fields. Validated on AWS. |
| **P2** | `AwsGen3Database1` (v1) | ✅ Done | Medium | 11 resources, cross-namespace bridge. Needs password Secret to deploy. |
| **P3** | `AwsGen3Compute1` (v1) | ✅ Done | High | 8 resources, EKS cluster. Not deployed (high-cost). |
| **P4** | `AwsGen3Foundation1` (revised) | ✅ Done | High | 31 resources, 3 feature flags, 4 bridges. Core of new architecture. |
| **P5** | `AwsGen3Database1` (revised) | ✅ Done | Low | Thin: 5-6 resources. Reads databasePrepBridge from Foundation1. |
| **P6** | `AwsGen3Compute1` (revised) | ✅ Done | Medium | Thin: 6-8 resources. Standard + Auto Mode variants. |
| **P7** | `AwsGen3Search1` | ⬜ Planned | Medium | Thin: 4 resources. Needs `opensearchservice` ACK controller. |
| **P8** | gen3-helm Application (Tier 5) | ⬜ Planned | Medium | ArgoCD Application + values mapping from bridge ConfigMaps |
| **P9** | `AwsGen3AppIAM1` (Tier 4) | ⬜ Planned | Medium | IRSA roles + SQS. Needs `sqs` ACK controller. |
| **P10** | LGTM Observability (Tier 6) | ⬜ Planned | Medium | Grafana + Loki + Mimir + Tempo Helm charts |
| **P11** | `AwsGen3Advanced1` (Tier 7) | ⬜ Future | Low | WAF, EFS, ElastiCache, CloudWatch. Multiple new controllers needed. |

---

## 10. Instance Values Example

```yaml
# Full staging deployment — Foundation1 (all flags true) + Tiers 1, 2, 3
# Account ID is NOT in values — injected at runtime via namespace annotation
instances:
  # Tier 0: Foundation (with all prep enabled)
  spoke1-foundation:
    kind: AwsGen3Foundation1
    namespace: spoke1
    spec:
      name: spoke1
      vpcCIDR: "10.1.0.0/16"
      publicSubnetCIDRs: ["10.1.240.0/24", "10.1.241.0/24"]
      privateSubnetCIDRs: ["10.1.0.0/20", "10.1.16.0/20"]
      availabilityZones: ["us-east-1a", "us-east-1b"]
      loggingBucketName: spoke1-logging
      dataBucketName: spoke1-data
      uploadBucketName: spoke1-upload
      # Feature flags — enable prep for all downstream tiers
      databaseEnabled: true
      computeEnabled: true
      searchEnabled: true
      # Database prep inputs
      dbSubnetCIDRs: ["10.1.32.0/24", "10.1.33.0/24"]
      createBridgeSecret: true

  # Tier 1: Database (thin — reads databasePrepBridge from Foundation)
  spoke1-database:
    kind: AwsGen3Database1
    namespace: spoke1
    syncWave: "2"
    spec:
      name: spoke1
      databasePrepBridgeName: spoke1-database-prep-bridge
      foundationNamespace: spoke1
      auroraEngineVersion: "16.6"
      masterPasswordSecretName: spoke1-aurora-password  # manual prereq
      createBridgeSecret: true

  # Tier 2: Search (thin — reads searchPrepBridge from Foundation)
  spoke1-search:
    kind: AwsGen3Search1
    namespace: spoke1
    syncWave: "2"
    spec:
      name: spoke1
      foundationBridgeName: spoke1-foundation-bridge
      searchPrepBridgeName: spoke1-search-prep-bridge
      foundationNamespace: spoke1
      openSearchInstanceType: "t3.small.search"
      createBridgeSecret: true

  # Tier 3: Compute (thin — reads computePrepBridge from Foundation)
  spoke1-compute:
    kind: AwsGen3Compute1
    namespace: spoke1
    syncWave: "2"
    spec:
      name: spoke1
      foundationBridgeName: spoke1-foundation-bridge
      computePrepBridgeName: spoke1-compute-prep-bridge
      foundationNamespace: spoke1
      kubernetesVersion: "1.31"
      eksAutoMode: false           # Standard mode with explicit node group
      nodeInstanceTypes: ["m5.xlarge"]
      nodeDesiredSize: 2
      createBridgeSecret: true

# Tier 5: Application (gen3-helm) — deployed as ArgoCD Application, not RGD instance
# This is configured in the ArgoCD addons, not in cluster-fleet infrastructure YAML:
#
#   apiVersion: argoproj.io/v1alpha1
#   kind: Application
#   metadata:
#     name: gen3-app
#   spec:
#     source:
#       repoURL: https://helm.gen3.org
#       chart: gen3
#       targetRevision: 0.3.3
#       helm:
#         values: |
#           global:
#             hostname: gen3.example.com
#             postgres:
#               host: <from database-bridge ConfigMap>
#             es:
#               endpoint: <from search-bridge ConfigMap or in-cluster>
```

> **Cross-tier references**: Each downstream tier reads upstream outputs via `externalRef`
> to the appropriate bridge ConfigMap(s). The instance values only need to provide the
> bridge ConfigMap name — all ARNs, IDs, and endpoints are resolved automatically.
> Account ID is resolved from the namespace annotation `services.k8s.aws/owner-account-id`
> (injected by `kind-local-test.sh inject-creds` or by IRSA in gen3-kro).
>
> **Foundation creates all bridges**: Unlike v1 where each tier managed its own prep
> infrastructure, Foundation1 pre-provisions everything. Downstream tiers are thin and
> fast to deploy because all underlying networking, encryption, and IAM are already ready.
