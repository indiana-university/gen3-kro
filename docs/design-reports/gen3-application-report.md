# Gen3 Application Layer — Service Analysis Report

> **Scope**: Application-layer analysis of the Gen3 data commons platform
> for platform engineering and operator reference.
>
> **Sources**: `references/gen3-helm/` (gen3-helm charts), Gen3 upstream
> documentation, and service-level `values.yaml` / `Chart.yaml` inspection.
>
> **Audience**: Platform engineers deploying Gen3 via KRO/ACK (gen3-kro)
> or Helm (gen3-helm). This document covers the **application services only**;
> for AWS infrastructure (VPC, EKS, Aurora, etc.), see
> `gen3-platform-research-report.md`.

---

## Table of Contents

1. [Service Inventory](#1-service-inventory)
2. [Service Dependency Diagram](#2-service-dependency-diagram)
3. [Request Flows and Workflows](#3-request-flows-and-workflows)
4. [Core Service Details](#4-core-service-details)
5. [Optional Service Details](#5-optional-service-details)
6. [AWS Service Dependencies](#6-aws-service-dependencies)
7. [Database Topology](#7-database-topology)
8. [Secrets and Configuration](#8-secrets-and-configuration)
9. [Deployment Model](#9-deployment-model)
10. [Operational Notes](#10-operational-notes)

---

## 1. Service Inventory

### 1.1 Core Services (Enabled by Default)

| # | Service | Role | Database | Image |
|---|---------|------|----------|-------|
| 1 | **revproxy** | Nginx ingress — TLS termination, path-based routing to all backends | None | `quay.io/cdis/nginx` |
| 2 | **fence** | Authentication — OIDC login, presigned URL generation, usersync | `fence` (PostgreSQL) | `quay.io/cdis/fence` |
| 3 | **arborist** | Authorization — RBAC policy engine, evaluates user.yaml / dbGaP | `arborist` (PostgreSQL) | `quay.io/cdis/arborist` |
| 4 | **indexd** | Data index — maps GUIDs to storage URLs (S3, GCS, Azure) | `indexd` (PostgreSQL) | `quay.io/cdis/indexd` |
| 5 | **sheepdog** | Data submission — validates records against the data dictionary | `sheepdog` (PostgreSQL) | `quay.io/cdis/sheepdog` |
| 6 | **peregrine** | Data query — GraphQL over the sheepdog/graph DB | Shares `sheepdog` DB | `quay.io/cdis/peregrine` |
| 7 | **portal** | Frontend UI — React SPA, explorer page, login flow | None | `quay.io/cdis/data-portal` |
| 8 | **metadata** | Metadata API — semi-structured JSON per GUID, aggregate MDS | `metadata` (PostgreSQL) + ES | `quay.io/cdis/metadata-service` |
| 9 | **audit** | Audit service — logs presigned-URL and login events from SQS | `audit` (PostgreSQL) | `quay.io/cdis/audit-service` |
| 10 | **hatchery** | Workspace launcher — provisions Jupyter/RStudio pods per user | None | `quay.io/cdis/hatchery` |
| 11 | **ambassador** | Envoy proxy — routes workspace sub-requests to user pods | None | `quay.io/datawire/ambassador:1.4.2` |
| 12 | **wts** | Workspace Token Service — exchanges fence tokens for workspace use | `wts` (PostgreSQL) | `quay.io/cdis/workspace-token-service` |
| 13 | **manifestservice** | Manifest service — creates file manifests in S3 for workspaces | None | `quay.io/cdis/manifestservice` |
| 14 | **etl** | ETL pipeline — reads graph DB, writes ElasticSearch indices | None (reads sheepdog DB) | `quay.io/cdis/tube` + `quay.io/cdis/gen3-spark` |
<!-- | 16 | **aws-es-proxy** | ES proxy — signs AWS requests to managed OpenSearch | None | AWS Managed OpenSearch | -->

### 1.2 Optional Services

| # | Service | Role | Database | When Needed |
|---|---------|------|----------|-------------|
| 15 | **guppy** | Explorer API — serves portal explorer page from ES indices | None (reads ES) | Explorer page |
| 17 | **ssjdispatcher** | Upload dispatcher — triggers indexing jobs from S3 events via SQS | None | Automated data upload |
<!-- | 18 | **sower** | Job dispatcher — runs pelican export/import jobs as K8s Jobs | None | Export manifest workflows | -->
| 19 | **requestor** | Access request — manages data-access request/approval workflow | `requestor` (PostgreSQL) | User access requests |
| 20 | **dashboard** | Dashboard — static data visualization pages | None | Operational dashboards |
| 21 | **argo-wrapper** | Argo integration — wraps Argo Workflows for pipeline execution | `argo` (PostgreSQL) | Workflow engine |
| 22 | **cohort-middleware** | Cohort analysis — OHDSI cohort definition middleware | None | OHDSI analytics |
| 23 | **datareplicate** | Replication — syncs data objects between S3 buckets | None | Multi-site sync |
| 24 | **frontend-framework** | Next-gen UI — replacement for portal (React/Next.js) | None | Newer deployments |
<!-- | 25 | **cedar** | CEDAR integration — NIH CEDAR metadata interop | None | NIH CEDAR | -->
| 26 | **access-backend** | Access backend — advanced access workflow engine | None | Access workflows |
| 27 | **data-upload-cron** | Upload cron — scheduled upload processing | None | Automated uploads |
| 28-31 | **dicom-server, ohif-viewer, orthanc, ohdsi-atlas/webapi** | Medical imaging + OHDSI analytics | PostgreSQL (some) | Imaging / OHDSI |

---

## 2. Service Dependency Diagram

The diagram below groups services into functional tiers. Arrows indicate
runtime dependencies (the caller depends on the callee). AWS managed
services are shown at the bottom.

```
 ═══════════════════════════════════════════════════════════════════════════════════════════════════
  TIER 0 — INGRESS
 ═══════════════════════════════════════════════════════════════════════════════════════════════════
                                         ┌──────────────────────────┐
                        ┌────────────────│         revproxy         │─────────────────┐
                        │                │   (nginx, TLS via ACM)   │                 │
                        │                └────────────┬─────────────┘                 │
                        │                             │                               │
 ═══════════════════════│═════════════════════════════│═══════════════════════════════│═════════════
  TIER 1 — FRONTENDS & ENTRY POINTS
 ═══════════════════════│═════════════════════════════│═══════════════════════════════│═════════════
                        ▼                             ▼                               ▼
                 ┌──────────────┐             ┌───────────────┐               ┌───────────────┐
                 │    portal    │             │     fence     │               │  ambassador   │
                 │ (React SPA)  │             │    (AuthN)    │               │  (envoy 1.4)  │
                 └──────┬───────┘             └───┬───┬───┬───┘               └───────┬───────┘
                        │                         │   │   │                           │
                        │                         │   │   │                           ▼
                        │                         │   │   │                   ┌───────────────┐
                        │                         │   │   │                   │   hatchery    │
                        │                         │   │   │         ┌─────────│  (workspace)  │
                        │                         │   │   │         │         └───────┬───────┘
                        │                         │   │   │         │                 │
 ═══════════════════════│═════════════════════════│═══│═══│═════════│═════════════════│═════════════
  TIER 2 — AUTH & WORKSPACE SUPPORT
 ═══════════════════════│═════════════════════════│═══│═══│═════════│═════════════════│═════════════
                        │                         │   │   │         │                 │
                        │                         │   │   ▼         ▼                 ▼
                        │                         │   │   ┌──────────┐        ┌───────────────┐
                        │                         │   │   │   wts    │        │manifestservice│
                        │                         │   │   │ (tokens) │        │     (S3)      │
                        │                         │   │   └──────────┘        └───────────────┘
                        │                         │   └──────────┐
                        │                         ▼              │
                        │                  ┌──────────────┐      │
                        │                  │   arborist   │      │
                        │                  │   (AuthZ)    │      │
                        │                  └──────────────┘      │
 ═══════════════════════│════════════════════════════════════════│══════════════════════════════════
  TIER 3 — DATA SERVICES  (revproxy also routes directly to each)
 ═══════════════════════│════════════════════════════════════════│══════════════════════════════════
                        │                                        │
                        │              ┌─────────────────────────┴─────────────────────────┐
                        │              │                │                 │                │
                        │              ▼                ▼                 ▼                ▼
                        │         ┌─────────┐     ┌────────────┐     ┌──────────┐     ┌──────────┐
                        │         │sheepdog │     │  metadata  │     │  indexd  │     │  audit   │
                        │         │(submit) │     │ (JSON/MDS) │     │ (GUIDs)  │     │ (log)    │
                        │         └────┬────┘     └─────┬──────┘     └──────────┘     └──────────┘
                        │              │                │
                        │              ▼                │ (optional: aggregate MDS)
                        │         ┌──────────┐          │
                        │         │peregrine │          │
                        │         │(GraphQL) │          │
                        │         └────┬─────┘          │
                        │              │                │
 ═══════════════════════│══════════════│════════════════│═══════════════════════════════════════════
  TIER 4 — SEARCH & ANALYTICS
 ═══════════════════════│══════════════│════════════════│═══════════════════════════════════════════
                        │              │                │
                        ▼              ▼                ▼
                   ┌──────────┐  ┌────────────┐  ┌──────────────┐
                   │  guppy   │  │  etl (job) │  │ aws-es-proxy │
                   │(explorer)│  │(tube+spark)│  │  (optional)  │
                   └────┬─────┘  └─────┬──────┘  └──────┬───────┘
                        │              │                │
                        └──────────────┼────────────────┘
                                       │
 ══════════════════════════════════════│════════════════════════════════════════════════════════════
  TIER 5 — AWS MANAGED SERVICES
 ══════════════════════════════════════│════════════════════════════════════════════════════════════
                                       ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                                 AWS Services                               │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────┐  ┌─────────┐  │
│  │ Aurora PostgreSQL │  │  OpenSearch / ES  │  │  S3       │  │  SQS    │  │
│  │ (6-8 databases)   │  │  (data indices)   │  │ (objects) │  │ (audit) │  │
│  └───────────────────┘  └───────────────────┘  └───────────┘  └─────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

### Key Relationships Not Shown in Tier Layout

| Caller | Callee | Interaction |
|--------|--------|-------------|
| fence | arborist | Checks AuthZ policies on every authenticated request |
| fence | indexd | Resolves GUIDs for presigned URL generation |
| fence → SQS | audit | Sends login + presigned-URL events; audit reads from SQS |
| sheepdog | indexd | Creates GUID entries during data submission |
| sheepdog | fence | Validates auth tokens on submission requests |
| peregrine | arborist | Filters GraphQL results by user authorization |
| portal | fence | Redirects to fence for OIDC login |
| portal | guppy | Explorer page queries ES indices via guppy |
| portal | sheepdog | Submission UI sends records via sheepdog API |
| portal | peregrine | Query UI runs GraphQL queries via peregrine API |
| hatchery | fence | Authenticates workspace launch requests |
| hatchery | wts | Obtains scoped tokens for the workspace session |
| hatchery | manifestservice | Mounts user file manifests into workspace pods |
| guppy | arborist | Filters explorer results by user AuthZ |
| etl | sheepdog DB | Reads graph data (direct PostgreSQL connection) |
| etl → aws-es-proxy | OpenSearch | Writes transformed indices |
| guppy → aws-es-proxy | OpenSearch | Reads indices for explorer queries |
| metadata → aws-es-proxy | OpenSearch | Optional aggregate metadata search |
| ssjdispatcher | SQS | Polls for S3 upload event notifications |
| ssjdispatcher | indexd | Triggers indexing jobs for uploaded files |

---

## 3. Request Flows and Workflows

### 3.1 User Login Flow

```
Browser ──► revproxy ──► portal ──► fence (/login) ──► OIDC Provider (e.g., Google, NIH)
                                        │
                                        ▼
                                   arborist  (load user policies from user.yaml)
                                        │
                                        ▼
                                  Return JWT to browser (stored as cookie)
```

1. User navigates to the commons URL. `revproxy` routes to `portal`.
2. Portal redirects unauthenticated users to `fence /login`.
3. Fence initiates OIDC flow with the configured identity provider.
4. On callback, fence creates a session, syncs the user's policies via
   `arborist` (from `user.yaml` or dbGaP telemetry), and returns a JWT.
5. The browser stores the JWT as an `access_token` cookie.

### 3.2 Data Submission Flow

```
Client (with JWT) ──► revproxy ──► sheepdog (/api/v0/submission/)
                                       │
                                   ┌───┴───┐
                                   ▼       ▼
                                 fence   indexd
                               (verify) (create GUID)
                                   │       │
                                   ▼       ▼
                              sheepdog DB  indexd DB
                              (graph node) (GUID → URL)
```

1. Authenticated client POSTs JSON/TSV records to `sheepdog`.
2. Sheepdog validates the JWT via `fence` and checks AuthZ against the project.
3. Sheepdog validates the record against the data dictionary schema.
4. For new data files, sheepdog calls `indexd` to create a GUID.
5. The graph node is committed to the `sheepdog` PostgreSQL database.

### 3.3 Data Query Flow (GraphQL)

```
Client (with JWT) ──► revproxy ──► peregrine (/api/v0/submission/graphql)
                                       │
                                   ┌───┴───┐
                                   ▼       ▼
                                 fence   arborist
                               (verify) (filter projects)
                                   │
                                   ▼
                              sheepdog DB (read-only query)
```

1. Client sends a GraphQL query to `peregrine`.
2. Peregrine validates auth via `fence`, checks project-level access via `arborist`.
3. Peregrine queries the graph database (sheepdog DB) and returns results.

### 3.4 Explorer Page Flow

```
Browser ──► revproxy ──► portal ──► guppy (/graphql)
                                       │
                                   ┌───┴───┐
                                   ▼       ▼
                                 fence   arborist
                               (verify) (filter)
                                   │
                                   ▼
                            aws-es-proxy ──► OpenSearch (read ES indices)
```

1. The portal explorer page sends queries to `guppy`.
2. Guppy validates auth, applies `arborist` access filters.
3. Guppy reads from ElasticSearch/OpenSearch indices (created by `etl`).
4. If using AWS Managed OpenSearch, requests pass through `aws-es-proxy`
   which signs them with AWS credentials.

### 3.5 ETL Pipeline Flow

```
                    ┌──────────────────┐
                    │  sheepdog DB     │  (graph data source)
                    └────────┬─────────┘
                             │ (direct PostgreSQL read)
                             ▼
                    ┌──────────────────┐
                    │  etl (tube job)  │  (K8s Job, Spark driver)
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  aws-es-proxy    │  (signs AWS requests)
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────┐
                    │    OpenSearch    │  (writes case/file indices)
                    └──────────────────┘
                             │
                    ┌────────┴─────────┐
                    ▼                  ▼
               ┌────────┐         ┌──────────┐
               │ guppy  │         │ metadata │ (aggregate MDS, optional)
               └────────┘         └──────────┘
```

1. ETL is a batch K8s Job (Spark + Tube) — not an always-running service.
2. Reads the graph data directly from the `sheepdog` PostgreSQL database.
3. Transforms records per `etlMapping.yaml` into flat ES documents.
4. Writes indices (e.g., `dev_case`, `dev_file`) to OpenSearch via `aws-es-proxy`.
5. `guppy` and optionally `metadata` (aggregate MDS) read from these indices.

### 3.6 Workspace Launch Flow

```
Browser ──► revproxy ──► portal ──► hatchery (/launch)
                                        │
                             ┌──────────┼──────────┐
                             ▼          ▼          ▼
                           fence       wts  manifestservice
                           (auth)     (tok)  (S3 manifest)
                                        │
                                        ▼
                                   K8s Pod (Jupyter/RStudio)
                                   in "jupyter-pods" namespace
                                         │
                                         ▼
                                     ambassador (routes sub-requests)
```

1. User clicks "Launch Workspace" in the portal.
2. Portal calls `hatchery`, which verifies the user via `fence`.
3. Hatchery requests a scoped token from `wts` for the workspace session.
4. Hatchery calls `manifestservice` to prepare the user's file manifest
   (reads from S3).
5. Hatchery creates a Jupyter/RStudio pod in the `jupyter-pods` namespace.
6. `ambassador` (envoy) proxies all subsequent HTTP traffic to the user's pod.

### 3.7 Audit Event Flow

```
fence (login or presigned-URL event) ──► SQS queue
                                             │
                                             ▼
                                         audit service
                                         (polls SQS)
                                             │
                                             ▼
                                         audit DB (PostgreSQL)
```

1. Fence sends audit events (login, presigned-URL access) to an SQS queue.
2. The `audit` service polls the SQS queue using IRSA credentials.
3. Events are stored in the `audit` PostgreSQL database for compliance review.

### 3.8 Upload Dispatch Flow (Optional)

```
S3 bucket (data upload) ──► S3 Event Notification ──► SQS queue
                                                          │
                                                          ▼
                                                    ssjdispatcher
                                                    (polls SQS)
                                                          │
                                                          ▼
                                                    K8s Job (indexing)
                                                          │
                                                          ▼
                                                       indexd (register GUID)
```

1. A data file is uploaded to S3.
2. S3 event notification sends a message to an SQS queue.
3. `ssjdispatcher` polls the queue and spawns a K8s indexing Job.
4. The job registers the file in `indexd` with a new GUID.

---

## 4. Core Service Details

### 4.1 revproxy

| Property | Value |
|----------|-------|
| **Purpose** | TLS-terminating Nginx reverse proxy; path-based routing to all services |
| **Database** | None |
| **Replicas** | 1 (default) |
| **AWS Dependencies** | ACM certificate (TLS), optional WAFv2 |
| **Depends on (services)** | All backend services (routes to them) |
| **Secrets** | TLS cert ARN via `revproxyArn` annotation |
| **Notes** | Internet-facing or internal scheme configurable |

### 4.2 fence

| Property | Value |
|----------|-------|
| **Purpose** | Central authentication: OIDC login, presigned URL generation, usersync |
| **Database** | `fence` (PostgreSQL) — users, clients, auth grants |
| **Replicas** | 1 (default); split deployment: `fence` + `presigned-url-fence` |
| **AWS Dependencies** | **S3** (data buckets for presigned URLs, user.yaml sync), **SQS** (publishes audit events), **Secrets Manager** (FENCE_CONFIG, JWT keys via ExternalSecrets) |
| **Depends on (services)** | arborist (AuthZ evaluation), indexd (GUID → URL for presigned URLs) |
| **Secrets** | `fence-config` (OIDC providers, S3_BUCKETS, AWS creds, dbGaP), `fence-jwt-keys` (RSA 4096 keypair), `fence-google-*-creds`, `fence-ssh-keys` (dbGaP SFTP) |
| **Key Config** | `FENCE_CONFIG` YAML blob: OIDC client_id/secret per provider, S3 bucket list, DB connection |
| **Notes** | The most configuration-heavy service. Usersync CronJob periodically pulls `user.yaml` from S3 or dbGaP SFTP |

### 4.3 arborist

| Property | Value |
|----------|-------|
| **Purpose** | Authorization engine — evaluates RBAC policies from user.yaml |
| **Database** | `arborist` (PostgreSQL) — policies, resources, roles |
| **Replicas** | 1 |
| **AWS Dependencies** | None directly |
| **Depends on (services)** | fence (triggers policy sync via usersync) |
| **Secrets** | DB credentials |
| **Key Config** | `rm_expired_access` CronJob cleans up expired access grants |

### 4.4 indexd

| Property | Value |
|----------|-------|
| **Purpose** | Data index — maps GUIDs to storage URLs |
| **Database** | `indexd` (PostgreSQL) — GUID records, hash values, storage URLs |
| **Replicas** | 1 |
| **AWS Dependencies** | **S3** (optional restore job) |
| **Depends on (services)** | fence (auth), sheepdog (writes GUIDs on submission) |
| **Secrets** | `indexd-service-creds` — contains passwords for fence, sheepdog, ssjdispatcher, gateway userdb |
| **Notes** | Shared auth secret means sheepdog and ssjdispatcher can write to indexd |

### 4.5 sheepdog

| Property | Value |
|----------|-------|
| **Purpose** | Data submission — validates records against the data dictionary schema |
| **Database** | `sheepdog` (PostgreSQL) — graph data model (nodes, edges) |
| **Replicas** | 1 |
| **AWS Dependencies** | None directly |
| **Depends on (services)** | fence (auth), indexd (GUID creation) |
| **Secrets** | DB credentials, settings.py volume mount |
| **Key Config** | `terminationGracePeriodSeconds: 50` — transactions need time to complete |

### 4.6 peregrine

| Property | Value |
|----------|-------|
| **Purpose** | Data query — GraphQL API over the graph database |
| **Database** | Shares `sheepdog` DB (read-only) or its own |
| **Replicas** | 1 |
| **AWS Dependencies** | None directly |
| **Depends on (services)** | fence (auth), arborist (project-level AuthZ filtering) |
| **Secrets** | DB credentials |
| **Key Config** | `arboristUrl` environment variable |

### 4.7 portal

| Property | Value |
|----------|-------|
| **Purpose** | Frontend SPA — login page, data explorer, submission UI |
| **Database** | None (stateless) |
| **Replicas** | 1-5 (autoscaling enabled by default) |
| **AWS Dependencies** | **S3** (logs bucket, kube manifest bucket) |
| **Depends on (services)** | revproxy (routing), fence (login), guppy (explorer page queries), sheepdog (submission UI), peregrine (query UI) |
| **Secrets** | None (config is inline: `gitops.json`, CSS, logos, favicon) |

### 4.8 metadata

| Property | Value |
|----------|-------|
| **Purpose** | Metadata API — stores semi-structured JSON per GUID; aggregate MDS |
| **Database** | `metadata` (PostgreSQL) + ElasticSearch (aggregate metadata) |
| **Replicas** | 1 |
| **AWS Dependencies** | **OpenSearch/ES** (aggregate MDS), **S3** (optional) |
| **Depends on (services)** | fence (auth), aws-es-proxy (if using AWS managed ES) |
| **Secrets** | DB credentials, `.env` config volume |
| **Key Config** | `esEndpoint: http://gen3-elasticsearch-master:9200`; init container runs Alembic DB migration |

### 4.9 audit

| Property | Value |
|----------|-------|
| **Purpose** | Audit logging — persists login and presigned-URL events for compliance |
| **Database** | `audit` (PostgreSQL) |
| **Replicas** | 1 |
| **AWS Dependencies** | **SQS** (reads audit events published by fence), **IAM/IRSA** (`eks.amazonaws.com/role-arn` annotation for SQS access) |
| **Depends on (services)** | fence (publishes events to SQS) |
| **Secrets** | DB credentials |

### 4.10 hatchery

| Property | Value |
|----------|-------|
| **Purpose** | Workspace launcher — creates per-user Jupyter/RStudio pods |
| **Database** | None |
| **Replicas** | 1 |
| **AWS Dependencies** | **EKS** (launches pods in cluster), **STS** (AssumeRole for CSOC admin), **RAM** (resource sharing for cross-account) |
| **Depends on (services)** | fence (auth), wts (workspace tokens), ambassador (envoy proxy), manifestservice (S3 file mount) |
| **Secrets** | Requires `fence-config` and `fence-jwt-keys` ExternalSecrets |
| **Key Config** | Requires VPC ID; sidecar runs a fence container for workspace auth |

### 4.11 ambassador

| Property | Value |
|----------|-------|
| **Purpose** | Envoy proxy — routes HTTP traffic to per-user workspace pods |
| **Database** | None |
| **Replicas** | 1 |
| **AWS Dependencies** | None |
| **Depends on (services)** | hatchery (creates the pods ambassador routes to) |
| **Key Config** | User namespace: `jupyter-pods`; `runAsUser: 8888`; 100Mi-400Mi memory |

### 4.12 wts

| Property | Value |
|----------|-------|
| **Purpose** | Workspace Token Service — exchanges fence tokens for workspace-scoped tokens |
| **Database** | `wts` (PostgreSQL) |
| **Replicas** | 1 |
| **AWS Dependencies** | None directly |
| **Depends on (services)** | fence (OIDC token exchange) |
| **Secrets** | `wts-g3auto`, `wts-oidc-client` (OIDC client config), DB credentials |

### 4.13 manifestservice

| Property | Value |
|----------|-------|
| **Purpose** | File manifest service — prepares S3 file manifests for workspace data access |
| **Database** | None |
| **Replicas** | 1 |
| **AWS Dependencies** | **S3** (reads/writes manifest files to `manifestservice-{vpc}-{ns}` bucket) |
| **Depends on (services)** | fence (auth), hatchery (consumer) |
| **Secrets** | AWS credentials or IRSA role |

### 4.14 etl

| Property | Value |
|----------|-------|
| **Purpose** | ETL pipeline — transforms graph DB records into flat ES indices |
| **Database** | None (reads `sheepdog` DB directly) |
| **Replicas** | K8s Job (batch, not always-running) |
| **AWS Dependencies** | **OpenSearch/ES** (write target for indices) |
| **Depends on (services)** | sheepdog DB (source), aws-es-proxy (ES transport), guppy (consumer) |
| **Secrets** | `etlMapping.yaml` ConfigMap |
| **Key Config** | Runs as Spark Job (tube + gen3-spark images); ES GC CronJob at `0 0 * * *` |

---

## 5. Optional Service Details

### 5.1 guppy

| Property | Value |
|----------|-------|
| **Purpose** | Explorer API — serves the portal explorer page from ES indices |
| **AWS Dependencies** | **OpenSearch/ES** (reads `dev_case`, `dev_file` indices) |
| **Depends on** | arborist (AuthZ filter), aws-es-proxy (if AWS managed ES), etl (creates the indices) |
| **Key Config** | `esEndpoint`, `guppy_config.json` ConfigMap |

### 5.2 aws-es-proxy

| Property | Value |
|----------|-------|
| **Purpose** | Signs HTTP requests to AWS Managed OpenSearch with IAM credentials |
| **AWS Dependencies** | **OpenSearch** (endpoint), **IAM** (AWS credentials for request signing) |
| **Depends on** | AWS Managed OpenSearch domain |
| **Key Config** | Port 9200; volume mounts `/root/.aws`; network policy allows ingress from guppy, metadata, spark, etl |
| **Notes** | Not needed if using self-hosted ElasticSearch inside the cluster |

### 5.3 ssjdispatcher

| Property | Value |
|----------|-------|
| **Purpose** | Upload dispatcher — polls SQS for S3 upload events, spawns indexing K8s Jobs |
| **AWS Dependencies** | **SQS** (listens for S3 event notifications), **S3** (source of upload events) |
| **Depends on** | indexd (target for new GUIDs) |
| **Key Config** | `dispatcherJobNum: 10`; `runAsUser: 1000` |

### 5.4 sower

| Property | Value |
|----------|-------|
| **Purpose** | Job dispatcher — runs pelican export/data-access jobs as K8s Jobs |
| **AWS Dependencies** | **S3** (KMS key for encrypted exports), **IAM/IRSA** (OIDC provider URL) |
| **Depends on** | fence (auth) |
| **Key Config** | `pelicanservice-g3auto` secret, `sower-jobs-g3auto` ConfigMap |

### 5.5 requestor

| Property | Value |
|----------|-------|
| **Purpose** | Access request management — users request access, admins approve |
| **Database** | `requestor` (PostgreSQL) |
| **Depends on** | fence (auth), arborist (policy check) |
| **Key Config** | Init container runs Alembic migration; optional Slack webhook for notifications |

### 5.6 dashboard

| Property | Value |
|----------|-------|
| **Purpose** | Static dashboard — serves pre-built data visualization pages |
| **AWS Dependencies** | **S3** (optional dashboard data bucket) |
| **Key Config** | `gitopsRepo` for dashboard configuration; image is `quay.io/cdis/gen3-statics` |

### 5.7 argo-wrapper

| Property | Value |
|----------|-------|
| **Purpose** | Wraps Argo Workflows for complex analysis pipeline execution |
| **Database** | `argo` (PostgreSQL) |
| **Depends on** | Argo Workflows CRDs |

---

## 6. AWS Service Dependencies

### 6.1 Summary Matrix

| AWS Service | Gen3 Services That Use It | Purpose |
|-------------|--------------------------|---------|
| **Aurora PostgreSQL** | fence, arborist, indexd, sheepdog/peregrine, metadata, audit, wts, requestor, argo-wrapper | Persistent data storage (6-9 databases per commons) |
| **S3** | fence, portal, manifestservice, ssjdispatcher, sower, dashboard, datareplicate, data-upload-cron | Data object storage, user.yaml sync, file manifests, logs |
| **OpenSearch (ES)** | etl, guppy, metadata, aws-es-proxy | Search indices for explorer page and aggregate metadata |
| **SQS** | fence → audit, ssjdispatcher, data-upload-cron | Asynchronous event messaging (audit events, upload notifications) |
| **Secrets Manager** | fence, arborist, indexd, sheepdog, wts (via ExternalSecrets) | Secure secret storage pulled into K8s Secrets at runtime |
| **ACM** | revproxy | TLS certificate for HTTPS termination |
| **WAFv2** | revproxy (optional) | Web Application Firewall for DDoS/bot protection |
| **IAM / IRSA** | audit, hatchery, sower, aws-es-proxy, ssjdispatcher | Service account → IAM role mapping for AWS API access |
| **STS** | hatchery | AssumeRole for CSOC admin workspace provisioning |
| **KMS** | sower, etl (optional) | Encryption keys for S3 objects |
| **EKS** | hatchery, ambassador | Pod provisioning (workspaces run as K8s pods) |
| **VPC Endpoints** | aws-es-proxy, audit, ssjdispatcher | Private connectivity to S3, SQS, OpenSearch without NAT |

### 6.2 IAM Roles Required

| IRSA Role | Service Account | Permissions |
|-----------|----------------|-------------|
| Audit SQS Reader | `audit-sa` | `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes` on the audit queue |
| Fence S3 + SQS | `fence-sa` | `s3:GetObject`, `s3:PutObject` on data buckets; `sqs:SendMessage` on audit queue |
| ES Proxy | `aws-es-proxy-sa` | `es:ESHttpGet`, `es:ESHttpPost` on the OpenSearch domain |
| SSJ Dispatcher | `ssjdispatcher-sa` | `sqs:ReceiveMessage`, `sqs:DeleteMessage` on upload queue |
| Manifestservice | `manifestservice-sa` | `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on manifest bucket |
| Hatchery | `hatchery-sa` | `sts:AssumeRole` to CSOC admin role; RAM permissions |

### 6.3 SQS Queues

| Queue | Publisher | Consumer | Message Content |
|-------|-----------|----------|-----------------|
| Audit queue | fence | audit | Login events, presigned-URL access records |
| Upload queue | S3 (event notification) | ssjdispatcher | S3 `PutObject` event with bucket/key |

### 6.4 S3 Buckets

| Bucket Pattern | Used By | Purpose |
|----------------|---------|---------|
| `{commons}-data-*` | fence (presigned URLs) | Research data objects |
| `manifestservice-{vpc}-{ns}` | manifestservice | Workspace file manifests |
| `{commons}-user.yaml` | fence (usersync) | Authorization config file |
| `logs-gen3` | portal, gen3 umbrella | Application logs |
| `kube-gen3` | portal, gen3 umbrella | Kubernetes manifest storage |
| `{commons}-dashboard` | dashboard | Dashboard static data |

---

## 7. Database Topology

All services connect to a shared **Aurora PostgreSQL** cluster. Each service
uses its own logical database within the cluster.

```
                    ┌───────────────────────────────┐
                    │   Aurora PostgreSQL Cluster   │
                    │                               │
                    │  ┌────────┐  ┌─────────────┐  │
                    │  │ fence  │  │  arborist   │  │
                    │  └────────┘  └─────────────┘  │
                    │  ┌────────┐  ┌─────────────┐  │
                    │  │ indexd │  │  sheepdog   │  │
                    │  └────────┘  │ (+ peregr.) │  │
                    │              └─────────────┘  │
                    │ ┌──────────┐  ┌───────────┐   │
                    │ │ metadata │  │  audit    │   │
                    │ └──────────┘  └───────────┘   │
                    │ ┌──────────┐  ┌───────────┐   │
                    │ │   wts    │  │requestor  │   │
                    │ └──────────┘  │ (optional)│   │
                    │               └───────────┘   │
                    └───────────────────────────────┘
```

| Database | Owner Service | Readers | Notes |
|----------|---------------|---------|-------|
| `fence` | fence | — | Users, OIDC clients, auth grants |
| `arborist` | arborist | — | Policies, resources, roles |
| `indexd` | indexd | — | GUID records, hash manifests |
| `sheepdog` | sheepdog | peregrine (read-only), etl (read-only) | Graph data model |
| `metadata` | metadata | — | Semi-structured JSON docs |
| `audit` | audit | — | Login + presigned-URL audit logs |
| `wts` | wts | — | Workspace token grants |
| `requestor` | requestor | — | Access request records (optional) |

**Security**: Each service should use a dedicated DB user with minimal
privileges. Sheepdog's DB is the only one with cross-service readers
(peregrine, etl use read-only credentials).

---

## 8. Secrets and Configuration

### 8.1 Secret Delivery Model

Gen3 supports two secret injection paths:

1. **ExternalSecrets** (recommended) — An ExternalSecrets operator pulls
   secrets from AWS Secrets Manager into K8s Secrets at runtime.
2. **Inline Helm values** — Secrets baked into `values.yaml` (not
   recommended for production).

### 8.2 Critical Secrets Inventory

| Secret Name | Service(s) | Contents | Source |
|-------------|------------|----------|--------|
| `fence-config` | fence, hatchery (sidecar) | OIDC providers, S3 bucket list, AWS credentials, dbGaP config | Secrets Manager |
| `fence-jwt-keys` | fence, hatchery (sidecar) | RSA 4096 keypair for signing JWTs | Secrets Manager |
| `fence-google-app-creds-secret` | fence | Google OIDC client credentials | Secrets Manager |
| `fence-ssh-keys` | fence | dbGaP SFTP SSH private key | Secrets Manager |
| `indexd-service-creds` | indexd | Service passwords for fence, sheepdog, ssjdispatcher | Secrets Manager |
| `wts-oidc-client` | wts | OIDC client_id + client_secret for workspace token exchange | Secrets Manager |
| `pelicanservice-g3auto` | sower | Pelican export job credentials | Secrets Manager |
| `{service}-dbcreds` | All DB services | `host`, `port`, `username`, `password`, `database` | Secrets Manager or inline |

### 8.3 ConfigMaps

| ConfigMap | Service | Contents |
|-----------|---------|----------|
| `manifest-guppy` | guppy | `guppy_config.json` — ES index names, auth config |
| `etl-mapping` | etl | `etlMapping.yaml` — field mappings from graph to ES |
| `sower-jobs-g3auto` | sower | Job templates for pelican export |
| `gitops-json` | portal | `gitops.json` — UI configuration, feature flags |

---

## 9. Deployment Model

### 9.1 Helm Umbrella Chart

All services are deployed as sub-charts of the `gen3` umbrella chart
(`references/gen3-helm/helm/gen3/`). The umbrella provides:

- **Global values**: AWS region, S3 bucket names, PostgreSQL master creds,
  ES endpoint, network policy toggle, ExternalSecrets toggle.
- **Per-service enable/disable**: Each service has `.enabled: true|false`.
- **Shared DB config**: A global `postgres` block for the Aurora connection.

### 9.2 Default Enable/Disable

| Enabled by Default | Disabled by Default |
|--------------------|--------------------|
| revproxy, fence, arborist, indexd, sheepdog, peregrine, portal, metadata, audit, hatchery, ambassador, wts, manifestservice, etl, guppy, ssjdispatcher, sower, requestor, dashboard | aws-es-proxy, cohort-middleware, datareplicate, cedar, access-backend, data-upload-cron, dicom-server, ohif-viewer, orthanc, ohdsi-atlas/webapi, frontend-framework |

### 9.3 Minimum Viable Deployment

For a functional Gen3 commons with data submission and query:

| Required | Purpose |
|----------|---------|
| revproxy | Ingress |
| fence | Authentication |
| arborist | Authorization |
| indexd | Data index |
| sheepdog | Submission |
| peregrine | Query |
| portal | UI |

**Add for search/explorer**: + etl, guppy, aws-es-proxy (if AWS ES)

**Add for workspaces**: + hatchery, ambassador, wts, manifestservice

**Add for audit compliance**: + audit (+ SQS queue)

---

## 10. Operational Notes

### 10.1 Startup Order

Services should become available in this order (enforced by readiness
probes and init containers, not sync-waves):

1. **Aurora PostgreSQL** + **OpenSearch** — AWS managed, must be ready first
2. **fence** — other services depend on it for auth
3. **arborist** — fence triggers usersync on startup
4. **indexd**, **sheepdog**, **peregrine**, **metadata**, **audit**, **wts** — backend services (no inter-dependency at startup)
5. **etl** — batch job, runs after graph DB has data
6. **guppy**, **aws-es-proxy** — need ES indices from etl
7. **portal** — frontend, needs backends to be healthy
8. **hatchery**, **ambassador**, **manifestservice** — workspace tier

### 10.2 Health Check Endpoints

| Service | Liveness | Readiness |
|---------|----------|-----------|
| fence | `/_status` | `/_status` |
| arborist | `/health` | `/health` |
| indexd | `/_status` | `/_status` |
| sheepdog | `/_status` | `/_status` |
| peregrine | `/_status` | `/_status` |
| metadata | `/_status` | `/_status` |
| guppy | `/_status` | `/_status` |
| revproxy | `/` | `/` |

### 10.3 Common Failure Modes

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| All logins fail | fence misconfigured (`FENCE_CONFIG`) or OIDC provider unreachable | Check `fence-config` secret, verify OIDC redirect URIs |
| Explorer page empty | ETL has not run, or ES indices missing | Run ETL job; check `etlMapping.yaml`; verify ES endpoint |
| Presigned URLs fail | fence cannot reach S3 or AWS credentials expired | Check IRSA role, verify S3 bucket policy |
| Audit events missing | SQS queue not receiving messages or IRSA misconfigured | Verify fence → SQS publish, audit IRSA role |
| Workspace launch fails | hatchery missing `fence-config` ExternalSecret or VPC ID unset | Verify ExternalSecrets, check `hatchery.vpcId` |
| "403 Forbidden" on valid user | arborist policies not synced from user.yaml | Trigger usersync job; verify `user.yaml` in S3 |
| GraphQL returns empty | peregrine DB credentials wrong or `sheepdog` DB empty | Check DB connection, verify data was submitted |

### 10.4 Scaling Considerations

| Service | Scaling Notes |
|---------|---------------|
| portal | Autoscaling enabled by default (1-5 replicas, HPA) |
| fence | Can run multiple replicas (stateless after JWT issuance) |
| guppy | CPU-bound on large ES queries; horizontal scaling effective |
| etl | Batch job — increase Spark resources, not replicas |
| sheepdog | Stateful transactions — scale carefully, `terminationGracePeriodSeconds: 50` |
| ambassador | Memory-limited (400Mi) — increase limits before adding replicas |