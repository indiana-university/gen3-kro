# Architecture

This document describes the hub-spoke architecture, component interactions, and design decisions.

## Overview

The gen3-kro platform implements a **hub-spoke cluster architecture** where:

- **Hub cluster**: Central EKS cluster running ArgoCD, KRO controller, and shared services
- **Spoke clusters**: Managed EKS clusters provisioned declaratively via KRO ResourceGraphDefinitions
- **GitOps**: All configuration stored in Git, synced by ArgoCD
- **Infrastructure as Code**: Terraform/Terragrunt for hub infrastructure

```
┌─────────────────────────────────────────────────────────────────┐
│                         Hub EKS Cluster                         │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  ArgoCD    │  │ KRO          │  │  Shared RGD Library     │ │
│  │  GitOps    │  │ Controller   │  │  • ekscluster.kro.run   │ │
│  │            │  │              │  │  • vpc-network          │ │
│  │ Monitors:  │  │ Watches:     │  │  • iam-roles            │ │
│  │ Git repo   │  │ EKSCluster   │  │  • efs-storage          │ │
│  │ Syncs apps │  │ resources    │  │  • security-groups      │ │
│  └────┬───────┘  └──────┬───────┘  └─────────────────────────┘ │
│       │                 │                                        │
│       │ Deploys         │ Creates                                │
│       ▼                 ▼                                        │
│  ┌─────────────────────────────────────────┐                    │
│  │        ACK Controllers                  │                    │
│  │  • ack-iam-controller                   │                    │
│  │  • ack-eks-controller                   │                    │
│  │  • ack-ec2-controller                   │                    │
│  └───────────────┬─────────────────────────┘                    │
└──────────────────┼──────────────────────────────────────────────┘
                   │
                   │ Provisions via AWS APIs
                   ▼
         ┌─────────────────────┐
         │   AWS Account(s)    │
         │  ┌──────────────┐   │
         │  │ Spoke Cluster│   │
         │  │   (EKS)      │   │
         │  │ • VPC        │   │
         │  │ • Subnets    │   │
         │  │ • NAT GW     │   │
         │  │ • Node Groups│   │
         │  └──────────────┘   │
         └─────────────────────┘
```

## Design Principles

### 1. Declarative Infrastructure

All infrastructure is declared as code:
- Hub infrastructure: Terraform modules + Terragrunt orchestration
- Spoke clusters: KRO ResourceGraphDefinitions
- Applications: Kubernetes manifests + ArgoCD Applications

**Benefits**:
- Version controlled
- Reproducible
- Self-documenting
- Auditable

### 2. GitOps Workflow

Git is the single source of truth:

```
Developer Workflow:
1. Edit config/spokes/my-spoke.yaml
2. git commit && git push
3. ArgoCD detects change
4. ArgoCD creates/updates Application
5. KRO controller reconciles EKSCluster resource
6. ACK controllers provision AWS resources
```

**Benefits**:
- Automated reconciliation
- Rollback via git revert
- Approval gates via pull requests
- Audit trail via git history

### 3. Separation of Concerns

```
┌─────────────────────────────────────┐
│ Platform Team                       │
│ • Manages hub cluster               │
│ • Defines shared RGD library        │
│ • Maintains spoke template          │
└─────────────────────────────────────┘
            │
            │ Provides self-service interface
            ▼
┌─────────────────────────────────────┐
│ Application Teams                   │
│ • Request spoke clusters            │
│ • Deploy applications               │
│ • Manage namespaces                 │
└─────────────────────────────────────┘
```

### 4. Multi-Account Support

Spokes can be deployed in different AWS accounts:

```
Hub Account (111111111111)
├── Hub EKS Cluster
│   └── KRO Controller (assumes roles)
│
Spoke Account 1 (222222222222)
├── IAM Role: spoke-provisioner (trusts hub)
└── Spoke Cluster 1
│
Spoke Account 2 (333333333333)
├── IAM Role: spoke-provisioner (trusts hub)
└── Spoke Cluster 2
```

**IAM Trust**:
```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::111111111111:role/hub-kro-controller-role"
  },
  "Action": "sts:AssumeRole"
}
```

## Components

### Hub Cluster

#### ArgoCD

**Purpose**: GitOps continuous delivery

**Key Resources**:
- `hub/argocd/bootstrap/hub-bootstrap.yaml`: App-of-apps root
- `hub/argocd/addons/`: Platform addons (KRO, ACK, metrics)
- `hub/argocd/fleet/spoke-fleet-appset.yaml`: Spoke fleet ApplicationSet

**ApplicationSet Pattern**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: spoke-fleet
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/infrastructure
        revision: main
        files:
          - path: "config/spokes/*.yaml"
  template:
    metadata:
      name: '{{name}}-infrastructure'
    spec:
      source:
        path: spokes/{{name}}
```

**Sync Waves**:
- `-3`: Controllers (KRO, ACK)
- `-1`: CRDs, namespaces
- `0`: Platform services
- `3`: Spoke clusters
- `5`: Applications

#### KRO Controller

**Purpose**: Orchestrate complex resource graphs

**Architecture**:
```
KRO Controller
├── Watches: Custom Resources (e.g., EKSCluster)
├── Reads: ResourceGraphDefinition
├── Generates: DAG of Kubernetes resources
└── Creates: Resources via ACK controllers
```

**Example Flow**:
1. User creates `EKSCluster` resource
2. KRO reads `ekscluster.kro.run` RGD
3. KRO generates:
   - VPC (via ACK EC2)
   - Subnets (via ACK EC2)
   - NAT Gateways (via ACK EC2)
   - IAM Roles (via ACK IAM)
   - EKS Cluster (via ACK EKS)
   - Node Groups (via ACK EKS)
4. ACK controllers create AWS resources
5. KRO monitors status and reports back

#### ACK Controllers

**Purpose**: Manage AWS resources from Kubernetes

**Installed Controllers**:
- **ack-iam-controller**: IAM roles, policies
- **ack-eks-controller**: EKS clusters, node groups
- **ack-ec2-controller**: VPCs, subnets, security groups

**Resource Mapping**:
```
Kubernetes Resource → AWS Resource
───────────────────────────────────
Role.iam.services.k8s.aws → IAM Role
Cluster.eks.services.k8s.aws → EKS Cluster
VPC.ec2.services.k8s.aws → VPC
```

### Shared RGD Library

**Location**: `shared/kro-rgds/aws/`

**Available RGDs**:

1. **ekscluster.kro.run**
   - Creates full EKS cluster with networking
   - Inputs: cluster name, version, VPC CIDR, node groups
   - Outputs: cluster endpoint, OIDC provider

2. **vpc-network**
   - Creates VPC with subnets across AZs
   - Inputs: CIDR, AZs, NAT configuration
   - Outputs: VPC ID, subnet IDs

3. **iam-roles**
   - Creates IAM roles with trust policies
   - Inputs: role name, trusted principals
   - Outputs: role ARN

4. **efs-storage**
   - Creates EFS filesystem with mount targets
   - Inputs: VPC, subnet IDs, encryption settings
   - Outputs: filesystem ID

5. **security-groups**
   - Creates security groups with rules
   - Inputs: VPC, ingress/egress rules
   - Outputs: security group IDs

### Spoke Clusters

**Provisioning**: Declarative via KRO

**Structure**:
```
spokes/
├── spoke-template/              # Template for new spokes
│   ├── infrastructure/
│   │   └── base/
│   │       └── eks-cluster-instance.yaml
│   ├── applications/
│   │   └── base/
│   │       └── kustomization.yaml
│   └── argocd/
│       └── base/
│           └── applications.yaml
└── my-spoke/                    # Instance created from template
    └── (same structure)
```

**Instance Creation**:
```yaml
# spokes/my-spoke/infrastructure/base/eks-cluster-instance.yaml
apiVersion: kro.run/v1alpha1
kind: EKSCluster
metadata:
  name: my-spoke-cluster
spec:
  clusterName: my-spoke-cluster
  version: "1.33"
  vpcCIDR: "10.1.0.0/16"
  # ... more config
```

## Data Flow

### Spoke Provisioning Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Developer commits config/spokes/my-spoke.yaml                │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. ArgoCD ApplicationSet detects new file                       │
│    Generates Application: my-spoke-infrastructure               │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. ArgoCD syncs Application                                     │
│    Creates: spokes/my-spoke/infrastructure/base/                │
│    Result: EKSCluster CR created in hub                         │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. KRO Controller reconciles EKSCluster                         │
│    • Reads ekscluster.kro.run RGD                               │
│    • Generates resource graph                                   │
│    • Creates child resources (VPC, Role, Cluster, etc.)         │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. ACK Controllers reconcile AWS resources                      │
│    • VPC controller creates VPC/subnets                         │
│    • IAM controller creates roles                               │
│    • EKS controller creates cluster/node groups                 │
└────────────┬────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Spoke cluster becomes ready                                  │
│    • KRO updates EKSCluster status                              │
│    • ArgoCD creates spoke Application (if configured)           │
│    • Applications deployed to spoke                             │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Hierarchy

```
config/config.yaml                      # Base configuration
       │
       ├─→ config/environments/staging.yaml   # Environment overlay
       │
       └─→ terraform/live/staging/terragrunt.hcl   # Terragrunt config
                  │
                  └─→ Terraform modules
                         │
                         └─→ AWS Resources
```

## Network Architecture

### Hub Cluster Network

```
VPC: 10.0.0.0/16
│
├─ Public Subnets (one per AZ)
│  ├─ 10.0.1.0/24 (us-east-1a)
│  ├─ 10.0.2.0/24 (us-east-1b)
│  └─ 10.0.3.0/24 (us-east-1c)
│  │
│  ├─ Internet Gateway
│  ├─ NAT Gateways (one per AZ)
│  └─ EKS API endpoint (if public)
│
└─ Private Subnets (one per AZ)
   ├─ 10.0.101.0/24 (us-east-1a)
   ├─ 10.0.102.0/24 (us-east-1b)
   └─ 10.0.103.0/24 (us-east-1c)
   │
   ├─ EKS node groups
   ├─ Pod networking (via AWS CNI)
   └─ Route to NAT Gateways
```

### Spoke Cluster Network

Each spoke gets its own isolated VPC:

```
Spoke 1: VPC 10.1.0.0/16
Spoke 2: VPC 10.2.0.0/16
Spoke 3: VPC 10.3.0.0/16
...
```

**Inter-spoke Communication** (optional):
- VPC Peering
- Transit Gateway
- PrivateLink

## Security Model

### IAM Architecture

```
Hub Cluster
├─ EKS Cluster IAM Role
├─ Node Group IAM Role
├─ KRO Controller Service Account
│  └─ IRSA → hub-kro-controller-role
│     └─ Can assume spoke provisioner roles
└─ ACK Controller Service Accounts
   ├─ IRSA → hub-ack-iam-controller-role
   ├─ IRSA → hub-ack-eks-controller-role
   └─ IRSA → hub-ack-ec2-controller-role

Spoke Account
└─ spoke-provisioner-role
   ├─ Trust: hub-kro-controller-role
   └─ Permissions: EKS, VPC, IAM (limited)
```

### RBAC

**Hub Cluster**:
- Platform admins: cluster-admin
- KRO controller: permissions to create/watch CRs
- ACK controllers: permissions to create ACK resources
- Application teams: namespace-scoped access

**Spoke Clusters**:
- Managed via spoke-specific RBAC
- ArgoCD deploys RBAC from Git
- Teams isolated by namespaces

### Encryption

- **EKS Secrets**: Encrypted with KMS
- **EBS Volumes**: Encrypted with KMS
- **S3 State**: Encrypted with AES-256
- **EFS**: Encrypted at rest and in transit

## Scalability

### Limits

**Hub Cluster**:
- ArgoCD: ~1000 Applications per cluster
- KRO: Limited by K8s API server (thousands of resources)
- ACK: Limited by AWS API rate limits

**Spoke Clusters**:
- Each spoke is independent EKS cluster
- No inherent limit on number of spokes
- Practical limit: Hub cluster resources

### Performance Optimization

**ArgoCD**:
- Use ApplicationSets for fleet management
- Configure sync intervals appropriately
- Use server-side diff

**KRO**:
- Resource graphs cached
- Parallel reconciliation
- Incremental updates

**Terragrunt**:
- Parallel module execution
- Remote state caching
- Plan artifacts

## Disaster Recovery

### Hub Cluster Failure

**RTO (Recovery Time Objective)**: 30-60 minutes  
**RPO (Recovery Point Objective)**: 0 (GitOps)

**Recovery Steps**:
1. Redeploy hub from Terraform
2. ArgoCD syncs from Git
3. KRO reconciles existing spokes

**Data Preserved**:
- All configuration in Git
- Terraform state in S3
- Spoke clusters unaffected

### Spoke Cluster Failure

**Recovery**:
1. Delete failed spoke config
2. Recreate spoke config
3. KRO provisions new cluster
4. ArgoCD deploys applications

**Data Loss**:
- Stateful data depends on backup strategy
- Use EBS snapshots, EFS backups

## Monitoring

### Hub Cluster

**Metrics**:
- ArgoCD sync status
- KRO reconciliation time
- ACK controller lag
- Cluster resource usage

**Alerts**:
- Application sync failures
- KRO reconciliation failures
- ACK API errors
- Node group health

### Spoke Clusters

**Metrics** (collected via spoke):
- Node/pod metrics
- Application-specific metrics
- Resource quotas

**Aggregation**:
- Prometheus federation
- CloudWatch (via ACK)
- Third-party observability platforms

## Design Decisions

### Why Hub-Spoke?

**Alternatives Considered**:
1. **Single large cluster**: Doesn't provide account/network isolation
2. **Fully independent clusters**: Duplicates control plane, harder to manage
3. **Hub-spoke with KRO**: Centralized management + isolation ✓

**Trade-offs**:
- More complex than single cluster
- Hub is single point of control (not failure)
- Requires cross-account IAM setup

### Why KRO over Other Tools?

**Alternatives**:
- **Terraform**: Less Kubernetes-native, not GitOps-friendly
- **Crossplane**: Similar but different composition model
- **Custom operators**: Reinventing the wheel

**KRO Advantages**:
- Kubernetes-native
- Declarative resource graphs
- Integrates with ArgoCD
- Extensible via RGDs

### Why ArgoCD?

**Alternatives**:
- **Flux**: Similar capabilities
- **Jenkins/Spinnaker**: Not GitOps-native

**ArgoCD Advantages**:
- Mature and widely adopted
- Excellent UI
- ApplicationSets for fleet management
- Strong RBAC

## Future Enhancements

### Planned

- Multi-region hub clusters (active/passive)
- Auto-scaling spokes based on metrics
- Cost optimization recommendations
- Self-service portal for spoke requests

### Under Consideration

- Service mesh (Istio/Linkerd)
- Multi-cluster observability (Thanos)
- Policy enforcement (Kyverno/OPA)
- Backup automation (Velero)

## References

- [KRO Documentation](https://kro.run/docs)
- [AWS ACK](https://aws-controllers-k8s.github.io/community/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Terragrunt](https://terragrunt.gruntwork.io/)
