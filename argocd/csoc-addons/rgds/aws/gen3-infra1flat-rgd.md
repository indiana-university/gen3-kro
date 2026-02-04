# Gen3 Infrastructure Deployment Dependency Chain

## Overview

This document describes the dependency chain and parallel provisioning strategy for Gen3 infrastructure deployment using Kro ResourceGraphDefinition.

**Graph**: `awsgen3infra1flat`
**Target**: AWS EKS + Aurora PostgreSQL + S3 + ArgoCD GitOps
**Node Management**: EKS Auto Mode (fully managed compute)

## Parallel Provisioning Levels

```
Level 1 (Foundation - 8 resources in parallel)
├── loggingKey        (KMS - logging encryption)
├── databaseKey       (KMS - database encryption)
├── searchKey         (KMS - search/cache encryption)
├── platformKey       (KMS - EKS secrets encryption)
├── vpc               (VPC - network foundation)
├── clusterRole       (IAM - EKS control plane role)
├── nodeRole          (IAM - EKS node role for Auto Mode)
└── eip1              (EIP - NAT gateway public IP)

Level 2 (Primary Resources - 6 resources in parallel)
├── igw               (Internet Gateway)
├── loggingBucket     (S3 - audit logs)
├── dataBucket        (S3 - application data)
├── uploadBucket      (S3 - user uploads)
├── eksSecurityGroup  (Security group - EKS cluster)
└── auroraSecurityGroup (Security group - PostgreSQL)

Level 3 (Public Routing - 1 resource)
└── publicRouteTable  (Route table - public subnet routing)

Level 4 (Public Subnets - 2 resources in parallel)
├── publicsubnet1     (Public subnet - AZ1)
└── publicsubnet2     (Public subnet - AZ2)

Level 5 (NAT Gateway - 1 resource)
└── natGateway1       (NAT Gateway - private subnet internet access)

Level 6 (Private Routing - 2 resources in parallel)
├── privateRouteTable (Route table - application tier)
└── dbRouteTable      (Route table - database tier, isolated)

Level 7 (Private Subnets - 4 resources in parallel)
├── privatesubnet1    (Private subnet - AZ1, application tier)
├── privatesubnet2    (Private subnet - AZ2, application tier)
├── dbsubnet1         (DB subnet - AZ1, database tier)
└── dbsubnet2         (DB subnet - AZ2, database tier)

Level 8 (Compute & Database Prep - 2 resources in parallel)
├── dbSubnetGroup     (RDS subnet group)
└── eksCluster        (EKS cluster with Auto Mode - 10-15 min)

Level 9 (Cluster Integration - 3 resources in parallel)
├── auroraCluster     (Aurora PostgreSQL cluster - 5-10 min)
├── spokeNamespace    (External reference - target namespace)
└── argoCDClusterSecret (Cluster registration secret)

Level 10 (Database Instances & Auth - 3 resources in parallel)
├── auroraInstance1   (Aurora reader instance 1)
├── auroraInstance2   (Aurora reader instance 2)
└── awsAuthApp        (ArgoCD App - aws-auth ConfigMap)

Level 11 (Application Deployment - 1 resource)
└── indexdApp         (ArgoCD App - indexd service)
```

## Provisioning Timeline

**Total Levels**: 11
**Maximum Parallelism**: 8 resources (Level 1)
**Estimated Duration**: 15-20 minutes (EKS cluster creation is longest operation)

**Critical Path**:
```
vpc → igw → publicRouteTable → publicsubnet1 → natGateway1 →
privateRouteTable → privatesubnet1 → eksCluster →
argoCDClusterSecret → awsAuthApp → indexdApp
```

## EKS Auto Mode Configuration

The RGD provisions EKS clusters using **Auto Mode**, which provides fully managed compute:

```yaml
spec:
  computeConfig:
    enabled: true                    # Enables EKS Auto Mode
    nodeRoleARN: <node-role-arn>    # IAM role for managed nodes
    nodePools:                       # Auto-created node pools
      - system                       # System workloads
      - general-purpose              # Application workloads
```

**Auto Mode Benefits**:
- ✅ No manual node group management required
- ✅ Automatic node scaling and rightsizing
- ✅ Managed system components (CoreDNS, kube-proxy, VPC CNI)
- ✅ Built-in security patching and updates
- ✅ No need for separate NodeGroup resources in RGD

**Verification**:
```bash
# Check cluster status
kubectl get clusters.eks.services.k8s.aws -n <namespace>

# Verify Auto Mode is enabled
kubectl get clusters.eks.services.k8s.aws <cluster-name> -n <namespace> \
  -o jsonpath='{.spec.computeConfig.enabled}'

# Check node pools
kubectl get clusters.eks.services.k8s.aws <cluster-name> -n <namespace> \
  -o jsonpath='{.spec.computeConfig.nodePools[*]}'
```

## Key Bottlenecks

1. **natGateway1** (Level 5)
   - Serializes public and private subnet creation
   - Required for private subnet internet access
   - Duration: ~2-3 minutes

2. **eksCluster** (Level 8)
   - **Primary bottleneck** - blocks all ArgoCD and application resources
   - Auto Mode cluster creation takes 10-15 minutes
   - Includes control plane + managed node provisioning
   - Blocks Levels 9-11 (cluster secret, applications)

3. **auroraCluster** (Level 9)
   - Required for indexd application deployment
   - Cluster + 2 instances creation: 5-10 minutes
   - Runs in parallel with ArgoCD cluster registration

## Dependency Patterns

**Kro Dependency Mechanisms**:
1. **readyWhen**: Self-references only for resource readiness
   ```yaml
   readyWhen:
     - ${eksCluster.status.?status.orValue('null') == 'ACTIVE'}
   ```

2. **Template Field References**: Creates implicit dependencies
   ```yaml
   roleARN: ${clusterRole.status.ackResourceMetadata.arn}  # Depends on clusterRole
   ```

3. **External References**: For pre-existing resources
   ```yaml
   externalRef:
     apiVersion: v1
     kind: Namespace
     name: spoke1
   ```

## Resource Count Summary

| Category | Resources | Level(s) |
|----------|-----------|----------|
| KMS Keys | 4 | 1 |
| Network (VPC, Subnets, Routing) | 15 | 1-7 |
| Storage (S3) | 3 | 2 |
| Security (IAM, SG) | 4 | 1-2 |
| Compute (EKS) | 1 | 8 |
| Database (Aurora) | 3 | 9-10 |
| GitOps (ArgoCD) | 2 | 9-10 |
| Applications | 1 | 11 |
| **Total** | **33** | **11 levels** |
