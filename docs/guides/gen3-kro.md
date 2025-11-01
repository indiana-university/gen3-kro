# Gen3 KRO Guide

Complete guide for deploying Gen3 infrastructure using Kubernetes Resource Orchestrator (KRO) with ResourceGraphDefinitions (RGDs) and instances.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [ResourceGraphDefinitions (RGDs)](#resourcegraphdefinitions-rgds)
4. [Prerequisites](#prerequisites)
5. [Deployment](#deployment)
6. [Customization](#customization)
7. [Environment Management](#environment-management)
8. [Troubleshooting](#troubleshooting)
9. [Appendix](#appendix)

---

## Overview

### What is Gen3 KRO?

Gen3 KRO provides declarative infrastructure patterns for Gen3 deployments using:

- **KRO (Kubernetes Resource Orchestrator)**: Defines reusable infrastructure patterns
- **ResourceGraphDefinitions (RGDs)**: Template-based resource definitions
- **AWS ACK Controllers**: Manage AWS resources from Kubernetes
- **ArgoCD**: GitOps-based continuous deployment
- **Kustomize**: Environment-specific configuration templating

### Key Benefits

✅ **Declarative Infrastructure**: Define infrastructure as Kubernetes resources
✅ **Reusable Patterns**: One RGD creates multiple instances
✅ **GitOps Ready**: Full ArgoCD integration with sync waves
✅ **Environment Flexibility**: Kustomize overlays for dev/staging/prod
✅ **Kubernetes-Native**: No external state management

---

## Architecture

### Directory Structure

```
argocd/graphs/
├── aws/
│   └── gen3/                    # Gen3-specific RGDs
│       ├── vpc-rgd.yaml         # VPC ResourceGraphDefinition
│       ├── kms-rgd.yaml         # KMS encryption keys
│       ├── s3bucket-rgd.yaml    # S3 buckets
│       ├── sns-rgd.yaml         # SNS topics
│       ├── sqs-rgd.yaml         # SQS queues
│       ├── secretsmanager-rgd.yaml    # Secrets Manager
│       ├── cloudwatch-logs-rgd.yaml   # CloudWatch Logs
│       ├── route53-rgd.yaml     # Route53 DNS
│       ├── rds-rgd.yaml         # RDS PostgreSQL
│       ├── aurora-rgd.yaml      # Aurora PostgreSQL
│       ├── elasticache-rgd.yaml # ElastiCache (Redis/Memcached)
│       ├── opensearch-rgd.yaml  # OpenSearch
│       ├── efs-rgd.yaml         # EFS file systems
│       ├── cloudtrail-rgd.yaml  # CloudTrail auditing
│       ├── waf-rgd.yaml         # WAF web application firewall
│       └── eks-rgd.yaml         # EKS clusters
└── instances/
    └── gen3/                    # Gen3 instance templates
        ├── vpc-instance.yaml    # VPC instance for deployment
        └── kustomization.yaml   # Kustomize configuration
```

### Key Concepts

**ResourceGraphDefinitions (RGDs)**
- Define infrastructure schemas and resource templates
- Register Custom Resource Definitions (CRDs) for KRO
- Located in `argocd/graphs/aws/gen3/`
- Deployed directly to `kro-system` namespace
- **NOT included in kustomization** (they're definitions, not instances)

**Instances**
- Concrete infrastructure implementations
- Reference RGDs to create actual resources
- Located in `argocd/graphs/instances/gen3/`
- Templated using Kustomize for environment customization
- Deployed to environment-specific namespaces

### Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          ArgoCD Hub                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Application: gen3-graphs                                       │
│  ├── Source: argocd/graphs/aws/gen3/                           │
│  ├── Destination: kro-system namespace                         │
│  └── Sync Wave Order:                                          │
│      -1: vpc-rgd.yaml, kms-rgd.yaml (foundation)               │
│       0: s3bucket-rgd.yaml, sns-rgd.yaml, sqs-rgd.yaml, etc.   │
│       1: rds-rgd.yaml, aurora-rgd.yaml, elasticache-rgd.yaml   │
│       2: eks-rgd.yaml (complex dependencies)                   │
│                                                                 │
│  Application: gen3-instances                                    │
│  ├── Source: argocd/graphs/instances/gen3/                    │
│  ├── Destination: default namespace (or per environment)       │
│  └── Uses: kustomize for templating                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Namespace: kro-system                                          │
│  ├── ResourceGraphDefinition: gen3vpc.kro.run                  │
│  ├── ResourceGraphDefinition: gen3kms.kro.run                  │
│  ├── ResourceGraphDefinition: gen3s3bucket.kro.run             │
│  ├── ResourceGraphDefinition: gen3sns.kro.run                  │
│  └── ... (all 16 RGDs)                                         │
│                                                                 │
│  Namespace: default (or dev/staging/prod)                       │
│  ├── Gen3Vpc: gen3-vpc-dev                                     │
│  ├── Gen3S3Bucket: gen3-data (when added)                      │
│  ├── Gen3RDS: gen3-postgres (when added)                       │
│  └── ... (other instances)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Resources                           │
├─────────────────────────────────────────────────────────────────┤
│  VPC, Subnets, RDS, ElastiCache, OpenSearch, S3, EKS, etc.     │
└─────────────────────────────────────────────────────────────────┘
```

---

## ResourceGraphDefinitions (RGDs)

### Complete RGD Inventory

**Total RGDs**: 16

#### Foundation Resources (Sync Wave: -1)

| File | Kind | Purpose | ACK Controller |
|------|------|---------|----------------|
| `vpc-rgd.yaml` | Gen3Vpc | VPC with subnets, IGW, NAT, route tables | EC2 |
| `kms-rgd.yaml` | Gen3KMS | KMS encryption keys with alias | KMS |

#### Storage & Messaging (Sync Wave: 0)

| File | Kind | Purpose | ACK Controller |
|------|------|---------|----------------|
| `s3bucket-rgd.yaml` | Gen3S3Bucket | S3 buckets with IAM policies | S3 |
| `sns-rgd.yaml` | Gen3SNS | SNS topics for notifications | SNS |
| `sqs-rgd.yaml` | Gen3SQS | SQS queues for messaging | SQS |
| `secretsmanager-rgd.yaml` | Gen3SecretsManager | Secrets in AWS Secrets Manager | SecretsManager |
| `cloudwatch-logs-rgd.yaml` | Gen3CloudWatchLogs | CloudWatch log groups | CloudWatchLogs |
| `route53-rgd.yaml` | Gen3Route53 | Route53 hosted zones | Route53 |

#### Infrastructure Services (Sync Wave: 1)

| File | Kind | Purpose | ACK Controller |
|------|------|---------|----------------|
| `rds-rgd.yaml` | Gen3RDS | PostgreSQL RDS instances | RDS |
| `aurora-rgd.yaml` | Gen3Aurora | Aurora PostgreSQL clusters | RDS |
| `elasticache-rgd.yaml` | Gen3ElastiCache | Redis/Memcached clusters | ElastiCache |
| `opensearch-rgd.yaml` | Gen3OpenSearch | OpenSearch domains | OpenSearch |
| `efs-rgd.yaml` | Gen3EFS | EFS file systems | EFS |
| `cloudtrail-rgd.yaml` | Gen3CloudTrail | CloudTrail audit logging | CloudTrail |
| `waf-rgd.yaml` | Gen3WAF | WAF web ACLs | WAFv2 |

#### Compute (Sync Wave: 2)

| File | Kind | Purpose | ACK Controller |
|------|------|---------|----------------|
| `eks-rgd.yaml` | Gen3EKS | EKS clusters with node groups | EKS |

### Status Field Exports

RGDs expose status fields for cross-resource dependencies:

**Gen3Vpc**
```yaml
status:
  vpcID: vpc-xxxxx
  publicSubnet1ID: subnet-xxxxx
  publicSubnet2ID: subnet-xxxxx
  privateSubnet1ID: subnet-xxxxx
  privateSubnet2ID: subnet-xxxxx
  internetGatewayID: igw-xxxxx
  natGateway1ID: nat-xxxxx
  natGateway2ID: nat-xxxxx
```

**Gen3S3Bucket**
```yaml
status:
  s3ARN: arn:aws:s3:::bucket-name
  s3Name: bucket-name
  s3PolicyARN: arn:aws:iam::account:policy/name
```

**Gen3RDS / Gen3Aurora**
```yaml
status:
  dbInstanceARN: arn:aws:rds:region:account:db:name
  endpoint: database.region.rds.amazonaws.com
  port: 5432
```

**Gen3EKS**
```yaml
status:
  clusterARN: arn:aws:eks:region:account:cluster/name
  clusterName: gen3-eks
  clusterEndpoint: https://xxxxx.eks.region.amazonaws.com
```

---

## Prerequisites

### Required Tools

- **kubectl** (v1.28+)
- **kustomize** (v5.0+)
- **ArgoCD** (v2.8+)
- **AWS CLI** (configured with credentials)

### Required AWS ACK Controllers

Install these ACK controllers in your cluster (16 total):

| Controller | Purpose | Installation |
|------------|---------|--------------|
| EC2 | VPC, subnets, security groups | `helm install ack-ec2-controller ...` |
| EKS | EKS clusters | `helm install ack-eks-controller ...` |
| RDS | RDS and Aurora databases | `helm install ack-rds-controller ...` |
| ElastiCache | Redis/Memcached | `helm install ack-elasticache-controller ...` |
| OpenSearch | OpenSearch domains | `helm install ack-opensearch-controller ...` |
| S3 | S3 buckets | `helm install ack-s3-controller ...` |
| EFS | EFS file systems | `helm install ack-efs-controller ...` |
| SNS | SNS topics | `helm install ack-sns-controller ...` |
| SQS | SQS queues | `helm install ack-sqs-controller ...` |
| KMS | KMS keys | `helm install ack-kms-controller ...` |
| SecretsManager | Secrets | `helm install ack-secretsmanager-controller ...` |
| IAM | IAM roles and policies | `helm install ack-iam-controller ...` |
| CloudWatchLogs | Log groups | `helm install ack-cloudwatchlogs-controller ...` |
| CloudTrail | Audit trails | `helm install ack-cloudtrail-controller ...` |
| WAFv2 | Web ACLs | `helm install ack-wafv2-controller ...` |
| Route53 | DNS zones | `helm install ack-route53-controller ...` |

### AWS Configuration

- AWS credentials with appropriate permissions
- VPC CIDR ranges planned (no overlaps)
- Region selected (default: us-east-1)
- IAM permissions for ACK controllers

---

## Deployment

### Phase 1: Deploy ResourceGraphDefinitions (RGDs)

RGDs must be deployed **before** instances to register CRDs.

#### Option A: Using ArgoCD (Recommended)

1. **Create ArgoCD Application**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gen3-graphs
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <your-git-repo>
    targetRevision: main
    path: argocd/graphs/aws/gen3
  destination:
    server: https://kubernetes.default.svc
    namespace: kro-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - SkipDryRunOnMissingResource=true
```

2. **Apply**:
```bash
kubectl apply -f gen3-graphs-app.yaml
```

3. **Verify**:
```bash
kubectl get resourcegraphdefinitions -n kro-system
```

Expected output (16 RGDs):
```
NAME                            AGE
gen3vpc.kro.run                10s
gen3kms.kro.run                10s
gen3s3bucket.kro.run           10s
gen3sns.kro.run                10s
gen3sqs.kro.run                10s
gen3secretsmanager.kro.run     10s
gen3cloudwatchlogs.kro.run     10s
gen3route53.kro.run            10s
gen3rds.kro.run                10s
gen3aurora.kro.run             10s
gen3elasticache.kro.run        10s
gen3opensearch.kro.run         10s
gen3efs.kro.run                10s
gen3cloudtrail.kro.run         10s
gen3waf.kro.run                10s
gen3eks.kro.run                10s
```

#### Option B: Using kubectl

```bash
kubectl apply -f argocd/graphs/aws/gen3/
kubectl get rgd -n kro-system
```

### Phase 2: Deploy Instances

Deploy instances **after** RGDs are registered.

#### Option A: Using ArgoCD (Recommended)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gen3-instances
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <your-git-repo>
    targetRevision: main
    path: argocd/graphs/instances/gen3
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: false  # Prevent accidental infrastructure deletion
      selfHeal: true
```

#### Option B: Using kubectl with kustomize

```bash
# Preview
kubectl kustomize argocd/graphs/instances/gen3/

# Apply
kubectl apply -k argocd/graphs/instances/gen3/
```

### Phase 3: Verify Deployment

```bash
# Check instances
kubectl get gen3vpc gen3-vpc-dev -o yaml

# View status fields
kubectl get gen3vpc gen3-vpc-dev -o jsonpath='{.status}'

# Verify AWS resources
kubectl get vpc,subnet,internetgateway -n gen3-dev

# Check ACK controller logs
kubectl logs -n ack-system deployment/ack-ec2-controller
```

---

## Customization

### Environment-Specific Instances

#### Development Environment

```yaml
# argocd/graphs/instances/gen3/overlays/dev/vpc-instance.yaml
apiVersion: kro.run/v1alpha1
kind: Gen3Vpc
metadata:
  name: gen3-vpc-dev
  namespace: dev
spec:
  name: gen3-dev
  region: us-east-1
  cidr:
    vpcCidr: "10.0.0.0/16"
    publicSubnet1Cidr: "10.0.1.0/24"
    publicSubnet2Cidr: "10.0.2.0/24"
    privateSubnet1Cidr: "10.0.11.0/24"
    privateSubnet2Cidr: "10.0.12.0/24"
```

#### Production Environment

```yaml
# argocd/graphs/instances/gen3/overlays/prod/vpc-instance.yaml
apiVersion: kro.run/v1alpha1
kind: Gen3Vpc
metadata:
  name: gen3-vpc-prod
  namespace: prod
spec:
  name: gen3-prod
  region: us-east-1
  cidr:
    vpcCidr: "10.1.0.0/16"
    publicSubnet1Cidr: "10.1.1.0/24"
    publicSubnet2Cidr: "10.1.2.0/24"
    privateSubnet1Cidr: "10.1.11.0/24"
    privateSubnet2Cidr: "10.1.12.0/24"
```

### Additional Infrastructure Examples

#### S3 Bucket

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3S3Bucket
metadata:
  name: gen3-data-bucket
spec:
  name: gen3-data-bucket-unique-id
  region: us-east-1
  access: write
```

#### RDS PostgreSQL

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3RDS
metadata:
  name: gen3-postgres
spec:
  name: gen3-postgres
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
    - ${gen3-vpc-dev.status.privateSubnet2ID}
  engine: postgres
  engineVersion: "15.4"
  instanceClass: db.t3.small
  allocatedStorage: 100
  databaseName: gen3
```

#### Aurora PostgreSQL

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3Aurora
metadata:
  name: gen3-aurora
spec:
  name: gen3-aurora
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
    - ${gen3-vpc-dev.status.privateSubnet2ID}
  engine: aurora-postgresql
  engineVersion: "15.4"
  instanceClass: db.t3.medium
  instanceCount: 2
  databaseName: gen3
```

#### ElastiCache Redis

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3ElastiCache
metadata:
  name: gen3-redis
spec:
  name: gen3-redis
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
    - ${gen3-vpc-dev.status.privateSubnet2ID}
  engine: redis
  engineVersion: "7.0"
  nodeType: cache.t3.small
  numCacheNodes: 1
```

#### OpenSearch

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3OpenSearch
metadata:
  name: gen3-opensearch
spec:
  name: gen3-opensearch
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
  engineVersion: "OpenSearch_2.11"
  instanceType: t3.small.search
  instanceCount: 1
  volumeSize: 50
```

#### EKS Cluster

```yaml
apiVersion: kro.run/v1alpha1
kind: Gen3EKS
metadata:
  name: gen3-eks
spec:
  name: gen3-eks
  region: us-east-1
  vpcID: ${gen3-vpc-dev.status.vpcID}
  subnetIDs:
    - ${gen3-vpc-dev.status.privateSubnet1ID}
    - ${gen3-vpc-dev.status.privateSubnet2ID}
  version: "1.28"
  nodeGroupInstanceTypes:
    - t3.medium
  nodeGroupDesiredSize: 3
  nodeGroupMinSize: 2
  nodeGroupMaxSize: 5
```

---

## Environment Management

### Strategy 1: Namespace-Based

```
dev namespace     → gen3-vpc-dev
staging namespace → gen3-vpc-staging
prod namespace    → gen3-vpc-prod
```

### Strategy 2: Kustomize Overlays

```
argocd/graphs/instances/gen3/
├── base/
│   ├── vpc-instance.yaml
│   └── kustomization.yaml
└── overlays/
    ├── dev/
    │   ├── vpc-instance.yaml
    │   └── kustomization.yaml
    ├── staging/
    └── prod/
```

Example overlay kustomization:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

resources:
  - ../../base

patches:
  - path: vpc-instance.yaml
```

### Strategy 3: ArgoCD ApplicationSet

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: gen3-instances-appset
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: dev
          - env: staging
            namespace: staging
          - env: prod
            namespace: prod
  template:
    metadata:
      name: 'gen3-instances-{{env}}'
    spec:
      source:
        path: 'argocd/graphs/instances/gen3/overlays/{{env}}'
      destination:
        namespace: '{{namespace}}'
```

---

## Troubleshooting

### RGD Not Found

**Problem**: `no matches for kind Gen3Vpc`

**Solution**:
```bash
# Verify RGD exists
kubectl get rgd gen3vpc.kro.run -n kro-system

# Deploy RGDs if missing
kubectl apply -f argocd/graphs/aws/gen3/
```

### Instance Stuck in Pending

**Problem**: Instance shows "Pending" status

**Solution**:
```bash
# Check instance events
kubectl describe gen3vpc gen3-vpc-dev

# Check ACK controller logs
kubectl logs -n ack-system -l app.kubernetes.io/name=ack-ec2-controller

# Verify AWS credentials
kubectl get secret -n ack-system
```

### CIDR Conflicts

**Problem**: Subnet creation fails

**Solution**:
- Verify CIDR ranges don't overlap
- Check VPC CIDR is large enough
- Ensure availability zones are valid

### ArgoCD Sync Failures

**Problem**: ArgoCD fails to sync

**Solution**:
```bash
# Check application status
kubectl get application gen3-instances -n argocd -o yaml

# View errors
argocd app get gen3-instances

# Manual sync
argocd app sync gen3-instances --replace
```

---

## Best Practices

### 1. Namespace Organization
- Separate namespaces per environment (dev/staging/prod)
- Keep RGDs in `kro-system`
- Deploy instances in environment namespaces

### 2. Secret Management
- Store passwords in AWS Secrets Manager
- Use External Secrets Operator for Kubernetes sync
- Never commit secrets to Git

### 3. Resource Naming
- Pattern: `<project>-<resource>-<environment>`
- Include unique IDs for global resources (S3)
- Tag all resources with environment/owner

### 4. GitOps Workflow
- Keep RGDs in `argocd/graphs/aws/gen3/`
- Keep instances in `argocd/graphs/instances/gen3/`
- Use branches for environment promotion
- Test in dev before prod

### 5. Monitoring
- Monitor ACK controller health
- Set CloudWatch alarms
- Use kubectl to inspect status
- Enable ArgoCD notifications

---

## Cleanup

### Delete Instances (Preserves RGDs)
```bash
kubectl delete gen3vpc gen3-vpc-dev
kubectl delete gen3vpc --all -n default
```

### Delete RGDs (Removes CRDs)
```bash
kubectl delete rgd -n kro-system -l app.kubernetes.io/part-of=gen3
```

### Complete Cleanup
```bash
# Instances first
kubectl delete -k argocd/graphs/instances/gen3/

# Then RGDs
kubectl delete -f argocd/graphs/aws/gen3/
```

---

## Appendix

### Sync Wave Reference

| Wave | Resources | Purpose |
|------|-----------|---------|
| -1 | VPC, KMS | Foundation |
| 0 | S3, SNS, SQS, Secrets, Logs, Route53 | Independent |
| 1 | RDS, Aurora, ElastiCache, OpenSearch, EFS, CloudTrail, WAF | VPC-dependent |
| 2 | EKS | Complex dependencies |

### Complete Status Field Reference

See individual RGD files for complete status field exports. Common patterns:

- **ARNs**: `${resource.status.ackResourceMetadata.arn}`
- **IDs**: `${resource.status.<resourceType>ID}`
- **Endpoints**: `${resource.status.endpoint}`
- **Names**: `${resource.metadata.name}`

### ACK Controller Health Check

```bash
# Check all ACK controllers
kubectl get pods -n ack-system

# Check specific controller
kubectl logs -n ack-system deployment/ack-ec2-controller --tail=50

# Check controller metrics
kubectl top pods -n ack-system
```

---

## Support

- **Issues**: Repository issue tracker
- **Documentation**: Update this guide as patterns emerge
- **Contributions**: Submit RGDs to shared library

---

**Last Updated**: November 2025
**Version**: 1.0
**RGD Count**: 16
