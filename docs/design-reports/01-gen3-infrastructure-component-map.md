# Gen3 Infrastructure & Application Component Map

> Generated from analysis of `references/gen3-helm` (application layer) and
> `references/gen3-terraform` (infrastructure reference).
> Purpose: Map every infrastructure and application component needed for Gen3,
> their dependencies, and whether they are required or optional.
>
> **Note**: gen3-dev manages infrastructure via KRO + ACK (not Terraform).
> Terraform references are included for completeness as the upstream pattern.

---

## 1. Gen3 Application Services

### 1.1 Core Services (enabled by default in gen3-helm)

| Service | Purpose | Databases Required | AWS Services Required | Depends On |
|---------|---------|-------------------|----------------------|------------|
| **fence** | Authentication, authorization tokens, data access credentials | PostgreSQL (`fence`) | SQS (audit queue, send), S3 (user.yaml, data upload), Secrets Manager (fence-config, jwt-keys) | — |
| **arborist** | Fine-grained authorization policy engine | PostgreSQL (`arborist`) | — | fence |
| **indexd** | Data object indexing (GUIDs → URLs) | PostgreSQL (`indexd`) | — | fence |
| **sheepdog** | Data submission (graph model) | PostgreSQL (`sheepdog`) | — | fence, arborist, indexd, peregrine |
| **peregrine** | Data query (GraphQL) | PostgreSQL (shares sheepdog's) | — | fence, arborist, indexd |
| **portal** | Web UI for the data commons | — | — | fence, arborist, revproxy |
| **revproxy** | Reverse proxy / ingress gateway | — | ACM certificate, ALB (via ingress) | — |
| **metadata** | Metadata service (aggregate metadata) | PostgreSQL (`metadata`) | — | fence, arborist |
| **audit** | Audit logging of all API calls | PostgreSQL (`audit`) | SQS (audit queue, receive) | fence |
| **hatchery** | Jupyter workspace launcher | — | EC2 (workspace pods), IAM (hatchery-sa role) | fence, arborist |
| **ambassador** | API gateway / routing | — | — | revproxy |
| **manifestservice** | Manifest file management for workspaces | — | S3 (manifest bucket), IAM (manifestservice-sa role) | fence |
| **wts** | Workspace Token Service (token exchange) | PostgreSQL (`wts`) | — | fence |
| **etl** | Extract-Transform-Load to ElasticSearch | — | — | sheepdog, peregrine, ElasticSearch/OpenSearch |

### 1.2 Optional Services (disabled by default)

| Service | Purpose | Databases Required | AWS Services Required | Depends On |
|---------|---------|-------------------|----------------------|------------|
| **guppy** | ElasticSearch-backed data exploration | — | ElasticSearch/OpenSearch (read) | fence, arborist, etl |
| **aws-es-proxy** | Proxy to AWS OpenSearch | — | OpenSearch domain, IAM credentials | — |
| **ssjdispatcher** | S3-to-indexd pipeline (auto-index on upload) | — | SQS (ssjdispatcher queue), S3 (data bucket events) | fence, indexd |
| **sower** | Job dispatching (batch jobs) | — | — | fence |
| **requestor** | Access request management | PostgreSQL (`requestor`) | — | fence, arborist |
| **argo-wrapper** | Argo Workflows integration | PostgreSQL (`argo`) | — | fence |
| **dashboard** | Usage analytics dashboard | — | S3 (dashboard bucket) | — |
| **cohort-middleware** | OHDSI/cohort analysis proxy | — | — | fence, arborist |
| **datareplicate** | Cross-bucket data replication | — | S3 (source/dest buckets) | — |
| **frontend-framework** | Next-gen UI framework | — | — | fence, revproxy |
| **cedar** | CEDAR metadata integration | — | — | fence |
| **gen3-workflow** | Workflow management | — | — | fence |
| **gen3-user-data-library** | User data library | — | — | fence |
| **dicom-server** | DICOM medical imaging server | PostgreSQL (`dicom-server`) | — | fence |
| **ohif-viewer** | OHIF medical image viewer | — | — | dicom-server |
| **orthanc** | Orthanc DICOM server | — | — | — |
| **ohdsi-atlas** | OHDSI Atlas analytics | — | — | ohdsi-webapi |
| **ohdsi-webapi** | OHDSI WebAPI | — | — | — |
| **gen3-analysis** | Gen3 analysis tools | — | — | fence |
| **neuvector** | Security policy enforcement | — | — | — |
| **data-upload-cron** | Periodic data upload jobs | — | S3 | fence |
| **embedding-management-service** | AI embeddings | — | — | — |

### 1.3 Database Summary

**PostgreSQL databases required per service** (all on single Aurora cluster):

| Database | Service | Required? |
|----------|---------|-----------|
| `fence` | fence | Yes (core) |
| `arborist` | arborist | Yes (core) |
| `indexd` | indexd | Yes (core) |
| `sheepdog` | sheepdog | Yes (core) |
| `peregrine` | peregrine | Shares sheepdog DB |
| `metadata` | metadata | Yes (core) |
| `audit` | audit | Yes (core) |
| `wts` | wts | Yes (core) |
| `requestor` | requestor | Optional |
| `argo` | argo-wrapper | Optional |
| `dicom` | dicom-viewer | Optional |
| `dicom-server` | dicom-server | Optional |

**Total: 8 required databases, 4 optional databases** (all on same Aurora instance)

---

## 2. AWS Infrastructure Components

### 2.1 Foundation Layer (Tier 0 — always required)

All infrastructure prep lives here. Feature flags (`databaseEnabled`,
`computeEnabled`, `searchEnabled`) control conditional resource groups.

#### Always-Present Resources

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| VPC | `ec2:VPC` | `ec2.services.k8s.aws/VPC` | Network isolation | — |
| Internet Gateway | `ec2:InternetGateway` | `ec2.services.k8s.aws/InternetGateway` | Public internet access | VPC |
| Elastic IP | `ec2:ElasticIPAddress` | `ec2.services.k8s.aws/ElasticIPAddress` | Static IP for NAT Gateway | — |
| NAT Gateway | `ec2:NATGateway` | `ec2.services.k8s.aws/NATGateway` | Private subnet internet egress | Public Subnet, EIP |
| Public Route Table | `ec2:RouteTable` | `ec2.services.k8s.aws/RouteTable` | Route public traffic to IGW | VPC, IGW |
| Private Route Table | `ec2:RouteTable` | `ec2.services.k8s.aws/RouteTable` | Route private traffic to NAT | VPC, NAT |
| Public Subnets (×2) | `ec2:Subnet` | `ec2.services.k8s.aws/Subnet` | ALB, NAT Gateway placement | VPC |
| Private Subnets (×2) | `ec2:Subnet` | `ec2.services.k8s.aws/Subnet` | EKS nodes, general workloads | VPC |
| Logging KMS Key | `kms:Key` | `kms.services.k8s.aws/Key` | Encrypt logs/S3/CloudTrail | — |
| Platform KMS Key | `kms:Key` | `kms.services.k8s.aws/Key` | Encrypt EKS secrets, application data (EKS service grant) | — |
| Logging S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Centralized logging | Logging KMS Key |
| Data S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Gen3 data objects | Platform KMS Key |
| Upload S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Upload staging | Platform KMS Key |

#### Database Prep Resources (conditional: `databaseEnabled`)

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| DB Route Table | `ec2:RouteTable` | `ec2.services.k8s.aws/RouteTable` | DB subnet routing to NAT | VPC, NAT |
| DB Subnets (×2) | `ec2:Subnet` | `ec2.services.k8s.aws/Subnet` | Isolated database subnet | VPC |
| DB Subnet Group | `rds:DBSubnetGroup` | `rds.services.k8s.aws/DBSubnetGroup` | RDS placement | DB Subnets |
| Database KMS Key | `kms:Key` | `kms.services.k8s.aws/Key` | Encrypt Aurora at rest (RDS service policy) | — |
| Aurora Security Group | `ec2:SecurityGroup` | `ec2.services.k8s.aws/SecurityGroup` | Port 5432 from VPC CIDR | VPC |

#### Compute Prep Resources (conditional: `computeEnabled`)

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| EKS Security Group | `ec2:SecurityGroup` | `ec2.services.k8s.aws/SecurityGroup` | EKS API 443 + kubelet 10250 from VPC CIDR | VPC |
| Cluster IAM Role | `iam:Role` | `iam.services.k8s.aws/Role` | EKS cluster service role (6 managed policies) | — |
| Node IAM Role | `iam:Role` | `iam.services.k8s.aws/Role` | EKS node group role (4 managed policies) | — |

#### Search Prep Resources (conditional: `searchEnabled`)

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| Search KMS Key | `kms:Key` | `kms.services.k8s.aws/Key` | Encrypt OpenSearch at rest (ES service policy) | — |
| OpenSearch Security Group | `ec2:SecurityGroup` | `ec2.services.k8s.aws/SecurityGroup` | Port 443 from VPC CIDR | VPC |

**Total: 16 always + 5 database + 3 compute + 2 search = 26 resources (+ 4 bridge ConfigMaps + 1 externalRef = 31)**

### 2.2 Compute Layer (Tier 3 — thin, EKS only)

All IAM and SG prep is done by Foundation (`computeEnabled`). This layer
creates only the cluster and node group.

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| EKS Cluster (Standard) | `eks:Cluster` | `eks.services.k8s.aws/Cluster` | Kubernetes control plane | VPC, Subnets, Cluster Role, EKS SG (all from Foundation) |
| EKS Node Group | `eks:Nodegroup` | `eks.services.k8s.aws/Nodegroup` | Worker nodes (Standard mode only) | EKS Cluster, Node Role, Private Subnets |
| EKS Cluster (Auto Mode) | `eks:Cluster` | `eks.services.k8s.aws/Cluster` | Auto Mode variant (computeConfig, storageConfig) | same as Standard |
| EKS Access Entry | `eks:AccessEntry` | `eks.services.k8s.aws/AccessEntry` | IAM → K8s RBAC mapping | EKS Cluster |
| ArgoCD Cluster Secret | `v1:Secret` | Native K8s | Register spoke in hub ArgoCD | EKS Cluster |

**Total: 5-6 resources** (Standard or Auto Mode cluster variant + optional access/ArgoCD)

### 2.3 Database Layer (Tier 1 — thin, Aurora only)

All networking, encryption, and SG prep is done by Foundation (`databaseEnabled`).
This layer creates only the Aurora cluster and instance(s).

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| Aurora Cluster | `rds:DBCluster` | `rds.services.k8s.aws/DBCluster` | PostgreSQL Serverless v2 cluster | DB Subnet Group, Aurora SG, DB KMS Key (all from Foundation) |
| Aurora Instance (primary) | `rds:DBInstance` | `rds.services.k8s.aws/DBInstance` | Primary database | Aurora Cluster |
| Aurora Instance (replica) | `rds:DBInstance` | `rds.services.k8s.aws/DBInstance` | Read replica (optional, HA) | Aurora Cluster |

**Total: 2-3 resources**

### 2.4 Search Layer (Tier 2 — thin, OpenSearch only)

KMS key and SG prep is done by Foundation (`searchEnabled`). This layer
creates only the OpenSearch domain.

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| OpenSearch Domain | `opensearchservice:Domain` | `opensearchservice.services.k8s.aws/Domain` | ElasticSearch-compatible search | VPC, Private Subnets, Search KMS Key, OpenSearch SG (all from Foundation) |

**Total: 1 resource**
> **Note**: ACK opensearchservice controller needed (not currently in gen3-dev's 7 controllers)

### 2.5 Storage Layer (included in Foundation Tier 0)

Core S3 buckets (Data, Upload, Logging) are part of Foundation's always-present
resources. Additional buckets are created by higher tiers or Tier 4 (AppIAM).

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| ~~Data S3 Bucket~~ | — | — | **In Foundation Tier 0** | Platform KMS Key |
| ~~Upload S3 Bucket~~ | — | — | **In Foundation Tier 0** | Platform KMS Key |
| ~~Logging S3 Bucket~~ | — | — | **In Foundation Tier 0** | Logging KMS Key |
| Manifest S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Workspace manifests (Tier 4 or 7) | Platform KMS Key |
| Dashboard S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Usage analytics (optional, Tier 7) | Platform KMS Key |
| Observability S3 Bucket | `s3:Bucket` | `s3.services.k8s.aws/Bucket` | Grafana/Loki/Mimir (optional, Tier 6) | Platform KMS Key |

**Total: 3 in Foundation + 3 in later tiers**

### 2.6 Messaging Layer (Tier 4 or 7 — audit pipeline)

| Component | AWS Resource | ACK API | Purpose | Dependencies |
|-----------|-------------|---------|---------|--------------|
| Audit SQS Queue | `sqs:Queue` | `sqs.services.k8s.aws/Queue` | Audit event pipeline (fence → audit) | — |
| SSJDispatcher SQS Queue | `sqs:Queue` | `sqs.services.k8s.aws/Queue` | S3 upload → indexd auto-indexing | — |

**Total: 2 queues**
> **Note**: ACK sqs controller needed (not currently in gen3-dev's 7 controllers)

### 2.7 IAM / IRSA Roles (per-service — required for production)

| Role | Service | Permissions | Required? |
|------|---------|-------------|-----------|
| Cluster Role | EKS | `eks:*`, `ec2:*`, `elasticloadbalancing:*` | Yes |
| Node Role | EKS | `ecr:Get*`, `ec2:Describe*`, `logs:*` | Yes |
| Fence SA Role | fence | SQS SendMessage (audit queue) | Yes |
| Audit SA Role | audit | SQS ReceiveMessage/Delete (audit queue) | Yes |
| Hatchery SA Role | hatchery | EC2 (workspaces), STS AssumeRole | Yes |
| ManifestService SA Role | manifestservice | S3 (manifest bucket) | Yes |
| ALB Controller Role | ingress | ELB, EC2, ACM, WAF, Shield | Yes |
| External Secrets SA Role | external-secrets | SecretsManager Get/List | Optional |
| Grafana SA Role | observability | S3 (observability bucket) | Optional |
| S3 Mountpoint SA Role | s3-mountpoint | S3 full access | Optional |
| ArgoCD Spoke Role | argocd | STS crossaccount | Production only |

**Total: 7 required + 4 optional roles**

### 2.8 Secrets Manager (optional — production recommended)

| Secret | Purpose | Required? |
|--------|---------|-----------|
| `{vpc}-{ns}-values` | Full Helm values | Optional |
| `{vpc}-{ns}-fence-config` | Fence YAML configuration | Recommended |
| `{vpc}-{ns}-fence-jwt-keys` | Fence RSA JWT signing keys | Recommended |
| `{vpc}-{ns}-aws-es-proxy-creds` | OpenSearch IAM credentials | Optional |
| Per-service DB creds (×8-12) | Database username/password | Recommended |

### 2.9 Optional Advanced Infrastructure

| Component | AWS Resource | Purpose | Dependencies |
|-----------|-------------|---------|--------------|
| WAF Web ACL | `wafv2:WebACL` | Web application firewall | ALB |
| ACM Certificate | `acm:Certificate` | TLS termination | Domain verification |
| Route53 Records | `route53:RecordSet` | DNS for hostname | Hosted Zone |
| VPC Endpoints | `ec2:VPCEndpoint` | Private AWS API access | VPC |
| CloudWatch Logs | `logs:LogGroup` | Centralized logging | — |
| ECR Repository | `ecr:Repository` | Custom container images | — |
| Cognito User Pool | `cognito-idp:UserPool` | Managed authentication | — |
| EFS File System | `efs:FileSystem` | Shared persistent storage | VPC, Private Subnets |
| ElastiCache Cluster | `elasticache:CacheCluster` | Session caching (Redis) | VPC, Private Subnets |
| SNS Topic | `sns:Topic` | Notifications | — |
| Lambda Function | `lambda:Function` | Custom event processing | — |

### 2.10 Observability Stack (Helm-deployed, not ACK-managed)

The Gen3 observability stack is deployed via separate Helm charts on the EKS
cluster, not as AWS-managed services via RGDs.

| Component | Helm Chart | Purpose | AWS Dependencies |
|-----------|-----------|---------|------------------|
| **Grafana** | lgtm-distributed (umbrella) | Dashboards, visualization | — |
| **Loki** | lgtm-distributed | Log aggregation | S3 (observability bucket via IRSA) |
| **Mimir** | lgtm-distributed | Long-term metrics storage | S3 (observability bucket via IRSA) |
| **Tempo** | lgtm-distributed | Distributed tracing (disabled by default) | — |
| **Alloy** | grafana/alloy | Telemetry collector (replaces Promtail) | — |
| **Faro Collector** | faro-collector | Frontend browser observability | — |

**AWS resources needed for observability:**
- S3 bucket for Mimir block storage + Loki chunks (from Foundation or Advanced tier)
- IRSA role for Loki/Mimir S3 access (from Application IAM tier)
- Optional: ALB ingress for Mimir remote write endpoint

### 2.11 Application Deployment Model (gen3-helm)

Gen3 application services are deployed via the `gen3` umbrella Helm chart,
managed by ArgoCD. This is NOT an RGD — it runs on the EKS cluster.

**Deployment modes:**

| Mode | `global.dev` | Databases | Search | Secrets | Use Case |
|------|-------------|-----------|--------|---------|----------|
| Dev | `true` | In-cluster PostgreSQL (Bitnami) | In-cluster ElasticSearch | Inline K8s Secrets | Local development, CI |
| Production | `false` | External Aurora (from Tier 1) | AWS OpenSearch (from Tier 2) | ExternalSecrets → Secrets Manager | Real deployments |

**Key global parameters:**

| Parameter | Purpose |
|-----------|---------|
| `global.hostname` | Commons URL (e.g., `data.example.com`) |
| `global.environment` | Environment name (used in ALB group, secret naming) |
| `global.dev` | Deploy in-cluster PostgreSQL + ES (`true`) vs external (`false`) |
| `global.aws.enabled` | Enable AWS ALB ingress + IRSA annotations |
| `global.revproxyArn` | ACM certificate ARN for TLS termination |
| `global.postgres.master.*` | Aurora writer endpoint, port, username, password |
| `global.externalSecrets.deploy` | Use ExternalSecret CRs to pull from Secrets Manager |

**Infrastructure → Application handoff:**

1. Infrastructure tiers (RGDs) create AWS resources and expose outputs via bridge ConfigMaps
2. Bridge ConfigMap values are injected into gen3-helm via ArgoCD ApplicationSet parameters
3. gen3-helm's db-setup Jobs create per-service databases on the Aurora cluster
4. ExternalSecrets operator pulls secrets from AWS Secrets Manager into K8s Secrets

---

## 3. Dependency Graph

```
  ┌────────────────────────────────────────────────────────────────────────┐
  │                    FOUNDATION LAYER  (Tier 0)                          │
  │                                                                        │
  │  Always-Present:                                                       │
  │   VPC ──► IGW ──► Public Route Table                                   │
  │    │      EIP ──► NAT Gateway                                          │
  │    ├──► Public Subnets (×2)                                            │
  │    ├──► Private Subnets (×2) ──► Private Route Table                   │
  │    │                                                                   │
  │   Logging KMS Key ──► Logging Bucket                                   │
  │   Platform KMS Key ──► Data Bucket, Upload Bucket                      │
  │                                                                        │
  │  ┌─ databaseEnabled ─────────────┐  ┌─ computeEnabled ──────────────┐  │
  │  │  DB Subnets (×2) ──► DB RT    │  │  EKS Security Group           │  │
  │  │  DB Subnet Group              │  │  Cluster IAM Role (6 policies)│  │
  │  │  Database KMS Key             │  │  Node IAM Role (4 policies)   │  │
  │  │  Aurora Security Group        │  │                               │  │
  │  │  → databasePrepBridge         │  │  → computePrepBridge          │  │
  │  └───────────────────────────────┘  └───────────────────────────────┘  │
  │  ┌─ searchEnabled ───────────────┐                                     │
  │  │  Search KMS Key               │  → foundationBridge (always)        │
  │  │  OpenSearch Security Group    │                                     │
  │  │  → searchPrepBridge           │                                     │
  │  └───────────────────────────────┘                                     │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │
                 ┌────────────────────┼────────────────────┐
                 │                    │                    │
                 ▼                    ▼                    ▼
         ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
         │ COMPUTE (T3)  │    │ DATABASE (T1) │    │  SEARCH (T2)  │
         │ thin — reads  │    │ thin — reads  │    │ thin — reads  │
         │ computePrep + │    │ databasePrep  │    │ searchPrep +  │
         │ foundation    │    │ bridge        │    │ foundation    │
         │ bridges       │    │               │    │ bridges       │
         │               │    │               │    │               │
         │ EKS Cluster   │    │ Aurora Cluster│    │ OpenSearch    │
         │ (Std or Auto) │    │ Aurora Inst.  │    │ Domain        │
         │ Node Group    │    │               │    │               │
         │ Access Entry  │    │ → database    │    │ → search      │
         │ → compute     │    │   Bridge      │    │   Bridge      │
         │   Bridge      │    │               │    │               │
         └───────┬───────┘    └───────┬───────┘    └───────┬───────┘
                 │                    │                    │
                 └────────────────────┼────────────────────┘
                                      │
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │                APPLICATION SUPPORT LAYER  (Tier 4 — AppIAM)            │
  │                                                                        │
  │  Manifest S3 Bucket         Audit SQS Queue                            │
  │  SSJDispatcher SQS Queue    IRSA Roles (fence, audit, hatchery, ...)   │
  │  Secrets Manager Secrets    External Secrets Operator                  │
  └───────────────────────────────────┬────────────────────────────────────┘
                                      │
                                      ▼
  ┌────────────────────────────────────────────────────────────────────────┐
  │                OPTIONAL / ADVANCED LAYER  (Tier 7)                     │
  │                                                                        │
  │  WAF, ACM Certificate, Route53, VPC Endpoints, CloudWatch Logs         │
  │  ECR, Cognito, EFS, ElastiCache, Dashboard Bucket, SNS, Lambda         │
  └────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Service → Infrastructure Dependency Matrix

| Service | VPC/Net | EKS | Aurora DB | OpenSearch | S3 | SQS | KMS | IAM (IRSA) | Secrets Mgr |
|---------|---------|-----|-----------|------------|-----|-----|-----|------------|-------------|
| fence | R | R | R (fence db) | - | R (upload) | R (audit) | R | R (fence-sa) | R (config, jwt) |
| arborist | R | R | R (arborist db) | - | - | - | - | - | O |
| indexd | R | R | R (indexd db) | - | - | - | - | - | O |
| sheepdog | R | R | R (sheepdog db) | - | - | - | - | - | O |
| peregrine | R | R | R (sheepdog db) | - | - | - | - | - | O |
| portal | R | R | - | - | - | - | - | - | - |
| revproxy | R | R | - | - | - | - | - | R (ALB) | - |
| metadata | R | R | R (metadata db) | - | - | - | - | - | O |
| audit | R | R | R (audit db) | - | - | R (audit) | - | R (audit-sa) | O |
| hatchery | R | R | - | - | - | - | - | R (hatchery-sa) | - |
| manifestservice | R | R | - | - | R (manifest) | - | - | R (manifest-sa) | O |
| wts | R | R | R (wts db) | - | - | - | - | - | O |
| etl | R | R | R (read) | R | - | - | - | - | - |
| guppy | R | R | - | R | - | - | - | - | - |
| aws-es-proxy | R | R | - | R | - | - | - | - | R (es creds) |
| ssjdispatcher | R | R | - | - | R (data) | R (ssjdisp) | - | - | - |

**R** = Required, **O** = Optional/Recommended, **-** = Not needed

---

## 4. Component Counts Summary

| Category | Required | Optional | Total |
|----------|----------|----------|-------|
| VPC/Networking | 13 | 0 | 13 |
| Compute (EKS) | 4-6 | 0 | 6 |
| Database (Aurora) | 7 | 0 | 7 |
| Search (OpenSearch) | 0 | 3 | 3 |
| Storage (S3) | 3 | 2 | 5 |
| Security (KMS) | 2 | 2 | 4 |
| Security (IAM) | 4 | 7 | 11 |
| Messaging (SQS) | 0 | 2 | 2 |
| Secrets Manager | 0 | 15+ | 15+ |
| Advanced | 0 | 11 | 11 |
| **Total** | **~33** | **~42** | **~77** |

---

## 5. Cost Drivers (Approximate Monthly)

| Component | Estimated Monthly Cost | Required? |
|-----------|----------------------|-----------|
| NAT Gateway | ~$32-45 | Yes |
| EKS Cluster | ~$72 | Yes (prod) |
| EKS Nodes (2× m5.xlarge) | ~$280 | Yes (prod) |
| Aurora Serverless v2 (0.5-4 ACU) | ~$45-350 | Yes (prod) |
| OpenSearch (t3.small.search) | ~$26-50 | Optional |
| ElastiCache (cache.t3.micro) | ~$12 | Optional |
| S3 (3 buckets, minimal) | ~$1-5 | Yes |
| KMS Keys (×4) | ~$4 | Yes |
| SQS Queues (×2) | ~$0-1 | Optional |
| EIP | ~$3.65 | Yes |
| ALB | ~$16-25 | Yes (prod) |
| Secrets Manager (5 secrets) | ~$2 | Optional |
| **Minimal test (no EKS/Aurora)** | **~$37** | |
| **Dev environment** | **~$200-400** | |
| **Production environment** | **~$500-900** | |
